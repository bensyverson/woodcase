//
//  ViewerScriptlessNavigationTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Navigating the viewer with no script at all.
///
/// The in-place navigation ``ViewerScript`` adds is an enhancement over links the server
/// already rendered, and the way to prove that is to never run the script: these tests
/// speak HTTP, read an `href` out of the markup, and ask the server for it — which is
/// exactly what a browser with JavaScript switched off does. Nothing here parses a page
/// the script would have rewritten, because with the script off nothing rewrites it.
///
/// `SleepyHollow` has no "load this page without JavaScript" option, so a browser test
/// cannot make this claim; a fetch of the same URLs can, and it is the honest shape for
/// it anyway.
@Suite("scriptless navigation", .hangGuard)
struct ViewerScriptlessNavigationTests {
    /// A running server over a copy of `batch.pen`, driven with `URLSession`.
    private struct Bench {
        let scratch: URL
        let file: URL
        let log: ActivityLog
        let server: ViewerServer
        let port: UInt16
        let session: URLSession

        init() async throws {
            scratch = try ViewerFixtures.scratch()
            file = try ViewerFixtures.copy("batch.pen", into: scratch)
            log = ActivityLog(home: scratch)
            server = ViewerServer(pages: { _ in ViewerPages.routes() })
            port = try await server.start(files: [file], port: 0, log: log)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = ViewerFixtures.requestBudget
            session = URLSession(configuration: configuration)
        }

        var fileID: String {
            ViewerFile(url: file).id
        }

        func get(_ path: String) async throws -> String {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200, "GET \(path)")
            return String(decoding: data, as: UTF8.self)
        }

        func stop() async {
            await server.stop()
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    /// The `href` of the first `<a>` whose class list holds one class, entities decoded.
    ///
    /// A hand-rolled reader rather than a parser: the pages are ours and a dependency to
    /// read one attribute would be a poor trade. It matches the class as a whole *token*
    /// rather than as a prefix of the attribute, because every row here carries two or
    /// three classes and the order is the component's business, not this test's.
    private func href(ofClass name: String, in html: String) throws -> String {
        let attribute = try Regex("class=\"([^\"]*)\"")
        let anchor = try String(#require(
            html.split(separator: "<a ").first { chunk in
                guard let classes = try? attribute.firstMatch(in: String(chunk))?[1].substring
                else { return false }
                return classes.split(separator: " ").contains(Substring(name))
            },
            "no <a> classed \(name) in the page"
        ))
        let match = try #require(
            try Regex("href=\"([^\"]+)\"").firstMatch(in: anchor),
            "the \(name) anchor has no href"
        )
        let href = try #require(match[1].substring, "the \(name) anchor's href is empty")
        return String(href).replacingOccurrences(of: "&amp;", with: "&")
    }

    @Test("The footer's step link is a real link to the next artboard's page")
    func steppingWorksWithoutTheScript() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let first = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01")
        let next = try href(ofClass: "v-step-next", in: first)
        #expect(next == "/files/\(bench.fileID)/artboards/Brd01")

        // Following it, with nothing but the server, lands on the artboard it named.
        let second = try await bench.get(next)
        #expect(second.contains("data-artboard=\"Brd01\""))
        #expect(second.contains(">Board</span>"))
        #expect(second.contains(">2 of 3<"))
    }

    @Test("An outline row is a real link that selects the node server-side")
    func selectingWorksWithoutTheScript() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let page = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01")
        let row = try href(ofClass: "v-outline-row", in: page)

        let selected = try await bench.get(row)
        // The box is drawn by the server, so the selection is right before any script
        // runs — which is the whole claim ``ViewerScript``'s contract makes.
        #expect(selected.contains("v-box is-selected"))
        #expect(selected.contains("v-outline-row is-selected"))
    }

    @Test("The breadcrumb up to the map is a real link, and the map's rows lead back down")
    func theWayUpAndDownWorksWithoutTheScript() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let page = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01")
        let up = try href(ofClass: "v-crumb-map", in: page)
        #expect(up == "/files/\(bench.fileID)")

        let map = try await bench.get(up)
        #expect(map.contains("id=\"v-map\""))
        let down = try href(ofClass: "v-artboard-row", in: map)
        #expect(down.hasPrefix("/files/\(bench.fileID)/artboards/"))
        #expect(try await bench.get(down).contains("id=\"v-stage\""))
    }
}
