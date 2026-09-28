//
//  ViewerExportTests.swift
//  WoodcaseViewerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import Woodcase
@testable import WoodcaseViewer

/// `GET /files/{file}/artboards/{artboard}/export` — one artboard, at a size and in a
/// format the CLI's own render and generate verbs support, as a download.
@Suite(.hangGuard)
struct ViewerExportTests {
    /// A scratch copy of a fixture and a context over it.
    private struct Bench {
        let scratch: URL
        let file: URL
        let context: ViewerContext

        init(_ fixture: String = "batch.pen") throws {
            scratch = try ViewerFixtures.scratch()
            file = try ViewerFixtures.copy(fixture, into: scratch)
            context = ViewerFixtures.context(files: [file], home: scratch)
        }

        func export(artboard: String, query: [String: String]) -> ViewerRequest {
            let path = "/files/\(ViewerFile(url: file).id)/artboards/\(artboard)/export"
            return ViewerRequest(
                http: HTTPRequest(method: .get, path: path, query: query, headers: [:], target: path),
                parameters: ["file": ViewerFile(url: file).id, "artboard": artboard],
                context: context
            )
        }

        func clean() {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    private func body(of response: HTTPResponse) throws -> Data {
        guard case let .data(data) = response.body else {
            throw ViewerError.renderFailed(artboard: "", file: "")
        }
        return data
    }

    /// The pixel size of a PNG body.
    private func size(ofPNG data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    // MARK: - Images

    @Test("Export at 2x PNG returns an image twice the artboard's size in points")
    func pngAtTwoTimes() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "png", "scale": "2"])
        )
        #expect(response.headers["Content-Type"] == "image/png")
        #expect(response.headers["Content-Disposition"]?.contains("attachment") == true)
        #expect(response.headers["Content-Disposition"]?.contains("batch-Canvas@2x.png") == true)

        // batch.pen's Canvas is 400x300 points.
        let size = try size(ofPNG: body(of: response))
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test("The form's empty longest-edge box is not a size of zero")
    func emptyMaximumEdgeIsIgnored() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        // What the Export form actually submits when nobody types in the edge box.
        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "png", "scale": "2", "max": ""])
        )
        let size = try size(ofPNG: body(of: response))
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test("Export at 1x PNG is the artboard's own size")
    func pngAtOneTimes() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "png", "scale": "1"])
        )
        let size = try size(ofPNG: body(of: response))
        #expect(size.width == 400)
        #expect(size.height == 300)
    }

    @Test("A maximum edge in points sizes the longer side, whatever the scale said")
    func pngAtAMaximumEdge() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "png", "scale": "3", "max": "200"])
        )
        let size = try size(ofPNG: body(of: response))
        #expect(size.width == 200)
        #expect(size.height == 150)
    }

    @Test("Export as PDF is a PDF, at the artboard's own size in points")
    func pdf() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "pdf"])
        )
        #expect(response.headers["Content-Type"] == "application/pdf")
        #expect(response.headers["Content-Disposition"]?.contains("batch-Canvas.pdf") == true)

        let data = try body(of: response)
        #expect(data.starts(with: Data("%PDF".utf8)))
    }

    // MARK: - Code

    @Test("Export as React returns the .tsx generate writes for this artboard")
    func react() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "react"])
        )
        #expect(response.headers["Content-Type"] == "text/plain; charset=utf-8")
        #expect(response.headers["Content-Disposition"]?.contains("Canvas.tsx") == true)

        let text = try String(decoding: body(of: response), as: UTF8.self)
        #expect(text.contains("export function Canvas"))
    }

    @Test("Export as the theme stylesheet returns what ThemeEmitter writes")
    func themeCSS() async throws {
        let bench = try Bench("parser-themed-variables.pen")
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "container", query: ["format": "theme-css"])
        )
        #expect(response.headers["Content-Disposition"]?.contains("theme.css") == true)
        let text = try String(decoding: body(of: response), as: UTF8.self)
        #expect(text.contains("--bgColor"))
    }

    @Test("Export as the manifest returns what ManifestEmitter writes")
    func manifest() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cnv01", query: ["format": "manifest"])
        )
        #expect(response.headers["Content-Type"] == "application/json; charset=utf-8")
        let text = try String(decoding: body(of: response), as: UTF8.self)
        #expect(text.contains("\"components\""))
    }

    // MARK: - Errors that teach

    @Test("An unknown format is refused, listing the ones that work")
    func unknownFormat() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        await #expect(throws: ViewerError.self) {
            try await ViewerEndpoints.export(
                bench.export(artboard: "Cnv01", query: ["format": "svg"])
            )
        }
    }

    @Test("A code target this document produces no file for is refused, not sent empty")
    func absentCodeTargetIsRefused() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        // batch.pen has no interactive states, so `generate react` writes no states.css.
        await #expect(throws: ViewerError.self) {
            try await ViewerEndpoints.export(
                bench.export(artboard: "Cnv01", query: ["format": "states-css"])
            )
        }
    }

    @Test("A reusable artboard exports the component file, not a page file")
    func componentArtboard() async throws {
        let bench = try Bench()
        defer { bench.clean() }

        let response = try await ViewerEndpoints.export(
            bench.export(artboard: "Cmp01", query: ["format": "react"])
        )
        #expect(response.headers["Content-Disposition"]?.contains("Component.tsx") == true)
    }
}
