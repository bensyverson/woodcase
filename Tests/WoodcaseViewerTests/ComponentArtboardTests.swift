//
//  ComponentArtboardTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// A reusable component definition is an artboard here, as it already is for
/// `woodcase shot` and `woodcase tree`.
///
/// The viewer used to expand for ``PenRefExpander/Purpose/export``, which strips every
/// definition from the tree — so `banking.pen`, whose top-level frames are *all* definitions and
/// whose two placed screens are refs to one of them, listed no artboards at all and
/// could not be opened. A definition is what a designer edits; an agent reading the
/// viewer has to be able to see one.
@Suite("Component definitions are artboards")
struct ComponentArtboardTests {
    @Test("GET /files lists banking.pen's component definitions among its artboards")
    func listsDefinitions() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("banking.pen", into: scratch)
        let context = ViewerFixtures.context(files: [file], home: scratch)

        let response = try await ViewerEndpoints.files(ViewerRequest(
            http: HTTPRequest(method: .get, path: "/files", query: [:], headers: [:], target: "/files"),
            parameters: [:],
            context: context
        ))
        guard case let .data(data) = response.body else {
            Issue.record("GET /files answered with no body")
            return
        }
        let report = try ViewerJSON.decoder.decode(FileListReport.self, from: data)
        let summary = try #require(report.files.first)
        #expect(summary.error == nil)

        let ids = summary.artboards.map(\.id)
        // The five definitions, in document order…
        #expect(ids.prefix(5) == ["nSNTs", "msdSu", "jl9It", "d4kAy", "Dt9Jv"])
        // …and the two screens placed on the canvas, which are refs to `nSNTs`.
        #expect(ids.contains("YGJ0d/nSNTs"))
        #expect(ids.contains("8ruxp/nSNTs"))
        #expect(summary.artboards.first { $0.id == "nSNTs" }?.width == 402)
    }

    @Test("A definition renders, and the artboard page and PNG both answer for it")
    func rendersADefinition() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = try ViewerFixtures.copy("batch.pen", into: scratch)
        let file = ViewerFile(url: url)
        let context = ViewerFixtures.context(files: [file.url], home: scratch)

        // `Cmp01` is batch.pen's reusable component: 60×24, never placed on the canvas.
        let prepared = try await context.renders.prepared(file)
        #expect(prepared.artboards.map(\.id) == ["Cnv01", "Brd01", "Cmp01"])

        let rendering = try await context.renders.png(artboard: "Cmp01", of: file)
        #expect(rendering.artboard.width == 60)
        #expect(!rendering.png.isEmpty)

        let request = ViewerRequest(
            http: HTTPRequest(
                method: .get,
                path: "/files/\(file.id)/artboards/Cmp01",
                query: [:],
                headers: [:],
                target: "/files/\(file.id)/artboards/Cmp01"
            ),
            parameters: ["file": file.id, "artboard": "Cmp01"],
            context: context
        )
        let html = try await ArtboardPageBuilder.page(request)
        #expect(html.contains("data-artboard=\"Cmp01\""))

        let png = try await ViewerEndpoints.artboard(request)
        #expect(png.headers["X-Woodcase-Width"] == "60.0")
    }
}
