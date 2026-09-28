//
//  RenderCacheTests.swift
//  WoodcaseViewerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import Woodcase
@testable import WoodcaseViewer

struct RenderCacheTests {
    /// Widens `Cnv01` on disk, so a stale cache is visible as a stale size.
    private func widen(_ file: URL, to width: Int, home: URL) async throws {
        try await PenFileTransaction.run(at: file, identity: "tester", log: ActivityLog(home: home), timeout: ViewerFixtures.lockBudget) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Cnv01", properties: ["kind.width": .int(width)]
            )))
        }
    }

    @Test("A prepared document carries the artboards with settled sizes and a revision")
    func preparesADocument() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("batch.pen", into: scratch))

        let prepared = try await ViewerFixtures.renders().prepared(file)
        #expect(prepared.artboards.map(\.id) == ["Cnv01", "Brd01", "Cmp01"])
        #expect(prepared.artboard(id: "Cnv01")?.width == 400)
        #expect(!prepared.revision.isEmpty)
        #expect(prepared.directory == scratch.resolvingSymlinksInPath())
    }

    @Test("A render is kept, so the file changing underneath is not seen until invalidated")
    func keepsRenders() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = try ViewerFixtures.copy("batch.pen", into: scratch)
        let file = ViewerFile(url: url)
        let cache = ViewerFixtures.renders()

        let first = try await cache.png(artboard: "Cnv01", of: file)
        #expect(first.artboard.width == 400)

        try await widen(url, to: 500, home: scratch)
        let stale = try await cache.png(artboard: "Cnv01", of: file)
        #expect(stale.artboard.width == 400)

        await cache.invalidate(file)
        let fresh = try await cache.png(artboard: "Cnv01", of: file)
        #expect(fresh.artboard.width == 500)
        #expect(fresh.png != first.png)
    }

    @Test("Warming renders every artboard, so the first request is already answered")
    func warmsEveryArtboard() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = try ViewerFixtures.copy("batch.pen", into: scratch)
        let file = ViewerFile(url: url)
        let cache = ViewerFixtures.renders()

        await cache.warm(file)
        // Proof it was cached: the file changes and the warm answer is unchanged.
        try await widen(url, to: 500, home: scratch)
        #expect(try await cache.png(artboard: "Cnv01", of: file).artboard.width == 400)
        #expect(try await cache.png(artboard: "Brd01", of: file).artboard.width == 200)
    }

    @Test("Warming the full-size renders leaves the map's thumbnails cold")
    func warmingLeavesThumbnailsCold() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("batch.pen", into: scratch))
        let cache = ViewerFixtures.renders()

        await cache.warm(file)
        #expect(await cache.isRendered(artboard: "Cnv01", of: file))
        #expect(await !cache.isRendered(
            artboard: "Cnv01", of: file, longestSide: ArtboardMap.thumbnailEdge
        ))
    }

    @Test("Warming the thumbnails renders every artboard at the map's cap")
    func warmsMapThumbnails() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("batch.pen", into: scratch))
        let cache = ViewerFixtures.renders()

        await cache.warm(file)
        await cache.warmThumbnails(file)
        for artboard in ["Cnv01", "Brd01", "Cmp01"] {
            #expect(await cache.isRendered(
                artboard: artboard, of: file, longestSide: ArtboardMap.thumbnailEdge
            ), "\(artboard) should be warm at the map's cap")
        }
    }

    @Test("A theme is part of the key, and a different theme is a different image")
    func keysOnTheme() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("parser-themed-variables.pen", into: scratch))
        let cache = ViewerFixtures.renders()

        let light = try await cache.png(artboard: "container", of: file, theme: ["mode": "light"])
        let dark = try await cache.png(artboard: "container", of: file, theme: ["mode": "dark"])

        #expect(light.artboard.width == 400)
        #expect(light.png != dark.png)
    }

    @Test("The size cap scales the render down and reports the scale it settled on")
    func capsTheLongestSide() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("batch.pen", into: scratch))
        let cache = ViewerFixtures.renders()

        #expect(try await cache.png(artboard: "Cnv01", of: file, longestSide: 100).scale == 0.25)
        // The cap never scales past the maximum: a 400-point artboard under a 4000-pixel
        // cap is rendered at 2×, not 10×.
        #expect(try await cache.png(artboard: "Cnv01", of: file, longestSide: 4000).scale == 2)
    }

    @Test("An unknown artboard names the ids the file does have")
    func namesAvailableArtboards() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("batch.pen", into: scratch))

        await #expect(throws: ViewerError.unknownArtboard(
            id: "Nope", file: file.id, available: ["Cnv01", "Brd01", "Cmp01"]
        )) {
            try await ViewerFixtures.renders().png(artboard: "Nope", of: file)
        }
    }

    @Test("A definition artboard is flagged reusable, a placed instance is flagged an instance")
    func flagsDefinitionsAndInstances() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("banking.pen", into: scratch))

        let prepared = try await ViewerFixtures.renders().prepared(file)
        let definition = try #require(prepared.artboard(id: "nSNTs"))
        let instance = try #require(prepared.artboard(id: "YGJ0d/nSNTs"))

        #expect(definition.isReusable)
        #expect(!definition.isInstance)
        #expect(instance.isInstance)
        #expect(!instance.isReusable)
    }

    @Test("A file that cannot be parsed throws rather than serving a blank image")
    func refusesToInventAnImage() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = scratch.appendingPathComponent("broken.pen")
        try Data("not json".utf8).write(to: url)

        await #expect(throws: (any Error).self) {
            try await ViewerFixtures.renders().png(artboard: "Cnv01", of: ViewerFile(url: url))
        }
    }
}
