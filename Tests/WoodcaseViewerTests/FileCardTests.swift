//
//  FileCardTests.swift
//  WoodcaseViewerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The dashboard's card grid and the render behind each card's thumbnail.
@Suite("dashboard file cards")
struct FileCardTests {
    // MARK: - Which artboard stands for a file

    @Test("A file's cover is the first artboard that is not a component definition")
    func coverSkipsDefinitions() {
        let cover = Artboard.cover(of: [
            Artboard(id: "Cmp01", name: "Button", width: 60, height: 24, isReusable: true),
            Artboard(id: "Slt01", name: "Slot", width: 60, height: 24, isSlot: true),
            Artboard(id: "Cnv01", name: "Canvas", width: 400, height: 300),
        ])
        #expect(cover?.id == "Cnv01")
    }

    @Test("A placed instance is a cover, because it is a screen rather than a part")
    func coverPrefersAnInstanceOverADefinition() {
        let cover = Artboard.cover(of: [
            Artboard(id: "nSNTs", name: "banking-home", width: 402, height: 874, isReusable: true),
            Artboard(id: "YGJ0d/nSNTs", name: "banking-home / Dark", width: 402, height: 874, isInstance: true),
        ])
        #expect(cover?.id == "YGJ0d/nSNTs")
    }

    @Test("A file whose top-level frames are all definitions covers with the first of them")
    func coverFallsBackToTheFirstArtboard() {
        let cover = Artboard.cover(of: [
            Artboard(id: "Cmp01", name: "Button", width: 60, height: 24, isReusable: true),
            Artboard(id: "Cmp02", name: "Card", width: 60, height: 24, isReusable: true),
        ])
        #expect(cover?.id == "Cmp01")
    }

    @Test("A file with no artboards has no cover")
    func coverOfNothingIsNothing() {
        #expect(Artboard.cover(of: []) == nil)
        #expect(PreviewFixtures.summary(id: "a", name: "tirekick", artboards: 0).cover == nil)
    }

    // MARK: - The card

    @Test("A card carries a lazily loaded thumbnail of its cover artboard")
    func cardShowsAThumbnail() {
        let html = FileCard(
            summary: PreviewFixtures.summary(id: "a1b2c3d4e5f6", name: "banking", artboards: 3),
            clock: PreviewFixtures.clock
        ).render()

        #expect(html.contains("v-file-card"))
        #expect(html.contains(ViewerLink.png(
            file: "a1b2c3d4e5f6",
            artboard: "Cnv00",
            maxEdge: RenderCache.dashboardThumbnailEdge
        )))
        #expect(html.contains("loading=\"lazy\""))
        #expect(html.contains("href=\"/files/a1b2c3d4e5f6\""))
    }

    @Test("A file that could not be parsed shows no thumbnail and says why")
    func brokenCardSaysWhy() {
        let html = FileCard(
            summary: PreviewFixtures.summary(id: "a", name: "broken", artboards: 0, error: "not JSON"),
            clock: PreviewFixtures.clock
        ).render()

        #expect(html.contains("is-broken"))
        #expect(html.contains(">unreadable<"))
        #expect(html.contains("title=\"not JSON\""))
        #expect(!html.contains("<img"))
    }

    // MARK: - The grid

    @Test("The files render as a card grid, most recent change first")
    func gridIsOrderedByLastChange() {
        let html = FileList(
            files: [
                PreviewFixtures.summary(id: "c", name: "quiet"),
                PreviewFixtures.summary(
                    id: "a", name: "old",
                    lastChange: FileListReport.LastChange(
                        time: PreviewFixtures.now.addingTimeInterval(-9000),
                        identity: "ben", op: .set, nodes: [], paths: []
                    )
                ),
                PreviewFixtures.summary(
                    id: "b", name: "fresh",
                    lastChange: FileListReport.LastChange(
                        time: PreviewFixtures.now.addingTimeInterval(-10),
                        identity: "claude-a", op: .set, nodes: [], paths: []
                    )
                ),
            ],
            clock: PreviewFixtures.clock,
            logPath: ".woodcase/activity.jsonl",
            eventCount: 3
        ).render()

        #expect(html.contains("v-file-cards"))
        #expect(!html.contains("v-file-rows"))
        let order = ["a", "b", "c"].map { id -> Int in
            html.range(of: "data-file=\"\(id)\"").map { html.distance(from: html.startIndex, to: $0.lowerBound) } ?? -1
        }
        // fresh (b) before old (a) before quiet (c).
        #expect(order[1] < order[0])
        #expect(order[0] < order[2])
    }

    // MARK: - The image behind the thumbnail

    @Test("The URL a card's thumbnail names is served as a PNG, capped at the card's size")
    func thumbnailResolvesToAnImage() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = try ViewerFixtures.copy("batch.pen", into: scratch)
        let context = ViewerFixtures.context(files: [url], home: scratch)

        let report = await PageData.files(context)
        let summary = try #require(report.files.first)
        let cover = try #require(summary.cover)
        #expect(cover.id == "Cnv01")

        var routes = ViewerPages.routes()
        routes.add(contentsOf: ViewerEndpoints.routes())
        let target = ViewerLink.png(
            file: summary.id, artboard: cover.id, maxEdge: RenderCache.dashboardThumbnailEdge
        )
        let http = try HTTPRequest.parse(head: "GET \(target) HTTP/1.1\r\n\r\n")
        guard case let .handler(handler, parameters) = routes.match(http) else {
            Issue.record("no route answers \(target)")
            return
        }
        let response = try await handler(
            ViewerRequest(http: http, parameters: parameters, context: context)
        )

        #expect(response.headers["Content-Type"] == "image/png")
        guard case let .data(png) = response.body else {
            Issue.record("the thumbnail route answered with no bytes")
            return
        }
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) <= RenderCache.dashboardThumbnailEdge)
        #expect(image.width > 0)
    }

    @Test("A card's thumbnail is kept, so a dashboard reload does not re-render it")
    func thumbnailIsCached() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = try ViewerFixtures.copy("batch.pen", into: scratch)
        let file = ViewerFile(url: url)
        let cache = ViewerFixtures.renders()

        let first = try await cache.png(
            artboard: "Cnv01", of: file, longestSide: RenderCache.dashboardThumbnailEdge
        )

        // Proof it was cached rather than merely renderable twice: the file changes on
        // disk and the second answer is the first one, byte for byte.
        try await PenFileTransaction.run(
            at: url, identity: "tester", log: ActivityLog(home: scratch),
            timeout: ViewerFixtures.lockBudget
        ) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Cnv01", properties: ["kind.width": .int(500)]
            )))
        }
        let warm = try await cache.png(
            artboard: "Cnv01", of: file, longestSide: RenderCache.dashboardThumbnailEdge
        )
        #expect(warm.png == first.png)

        // And the card's cap is its own key: the artboard view's full-size render is a
        // different entry, so a warm page render is not what a card would have loaded.
        await cache.invalidate(file)
        let fresh = try await cache.png(
            artboard: "Cnv01", of: file, longestSide: RenderCache.dashboardThumbnailEdge
        )
        #expect(fresh.artboard.width == 500)
    }
}
