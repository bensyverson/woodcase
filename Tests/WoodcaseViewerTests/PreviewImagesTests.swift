//
//  PreviewImagesTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Every image a preview state draws is an image, on both hosts.
///
/// A state's markup is production markup, so its `<img>` points at the production route
/// — `/files/{file}/artboards/{artboard}.png` — for a fixture file no host serves. Until
/// the catalog carried its own render, every one of those answered a 404 and the preview
/// showed WebKit's broken-image glyph with the `alt` text drawn under the overlay (issue
/// `4FmPKE`). Walked over every state rather than named, so a new state pointing at a new
/// fixture file fails here rather than in a review shot.
@Suite(.serialized, .hangGuard)
struct PreviewImagesTests {
    /// Every distinct `src` any state in the catalog asks for, whole pages included.
    static var sources: [String] {
        var found: Set<String> = []
        for component in PreviewCatalog.all {
            for state in component.states {
                for match in state.render().matches(of: /<img[^>]* src="([^"]+)"/) {
                    found.insert(String(match.output.1).replacingOccurrences(of: "&amp;", with: "&"))
                }
            }
        }
        return found.sorted()
    }

    /// The eight bytes every PNG file opens with.
    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Fetches a path from a running server.
    private static func get(_ path: String, port: UInt16) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ViewerFixtures.requestBudget
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        return (data, response as! HTTPURLResponse)
    }

    @Test("Every image a preview draws answers 200 with a PNG on the `preview` host, as production does")
    func everyImageResolvesWithNoFiles() async throws {
        let server = ViewerServer(pages: { _ in ViewerPages.routes() })
        let port = try await server.start(files: [], port: 0, logs: [])
        defer { Task { await server.stop() } }
        // The walk has to walk something, or an empty catalog passes it.
        try #require(Self.sources.count >= 3)

        for source in Self.sources {
            let (data, response) = try await Self.get(source, port: port)
            #expect(response.statusCode == 200, "\(source) answered \(response.statusCode)")
            // The URL says `.png` and production answers it with PNG bytes, so the
            // catalog does too: an SVG at a `.png` address is a lie a download keeps.
            let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(type == "image/png", "\(source) is \(type), not a PNG")
            #expect(data.starts(with: Self.pngSignature), "\(source) is not PNG bytes")
        }
    }

    @Test("The same images answer beside a real file, so `serve` shows the previews the same way")
    func everyImageResolvesBesideARealFile() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let server = ViewerServer(pages: { _ in ViewerPages.routes() })
        let port = try await server.start(files: [file], port: 0, log: ActivityLog(home: scratch))
        defer { Task { await server.stop() } }

        for source in Self.sources {
            let (data, response) = try await Self.get(source, port: port)
            #expect(response.statusCode == 200, "\(source) answered \(response.statusCode)")
            let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(type == "image/png", "\(source) is \(type), not a PNG")
            #expect(data.starts(with: Self.pngSignature), "\(source) is not PNG bytes")
        }
    }
}
