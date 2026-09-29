//
//  ViewerPagesTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The page's routes, driven over a real socket.
///
/// The subject here is *the page as served* — that `/` and `/files/{file}` are real
/// pages, that a fragment is one element, and that nothing on any of them needs the
/// script to be correct.
///
/// Serialized: every case here binds a socket and warms a render, and a dozen of those
/// in parallel is a dozen live loopback servers in one process. The concurrent font
/// lookups this comment used to blame are handled at the source now — ``FontRegistryGate``
/// lets one thread at a time into CoreText's registry daemon — but the sockets are
/// reason enough on their own.
@Suite(.serialized, .hangGuard)
struct ViewerPagesTests {
    /// A running server with the page routes registered, over a copy of `batch.pen`.
    private struct Bench {
        let scratch: URL
        let file: URL
        let log: ActivityLog
        let server: ViewerServer
        let port: UInt16
        let session: URLSession

        init(files: [String] = ["batch.pen"]) async throws {
            scratch = try ViewerFixtures.scratch()
            let root = scratch
            let copied = try files.map { try ViewerFixtures.copy($0, into: root) }
            file = copied[0]
            log = ActivityLog(home: scratch)
            server = ViewerServer(pages: { _ in ViewerPages.routes() })
            port = try await server.start(files: copied, port: 0, log: log)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = ViewerFixtures.requestBudget
            session = URLSession(configuration: configuration)
        }

        var fileID: String {
            ViewerFile(url: file).id
        }

        func url(_ path: String) -> URL {
            URL(string: "http://127.0.0.1:\(port)\(path)")!
        }

        func get(_ path: String) async throws -> (String, HTTPURLResponse) {
            var request = URLRequest(url: url(path))
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            return (String(decoding: data, as: UTF8.self), response as! HTTPURLResponse)
        }

        func bytes(_ path: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url(path))
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            return (data, response as! HTTPURLResponse)
        }

        func stop() async {
            await server.stop()
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    @Test("GET / is the dashboard, listing the served file")
    func dashboardIsServed() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/")
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
        #expect(html.contains("<title>Files · woodcase serve</title>"))
        #expect(html.contains("href=\"/files/\(bench.fileID)\""))
        #expect(html.contains("v-layout-dashboard"))
    }

    @Test("A server watching nothing serves the empty page, not an empty dashboard")
    func emptyServerServesTheEmptyPage() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let server = ViewerServer(pages: { _ in ViewerPages.routes() })
        let port = try await server.start(files: [], port: 0, log: ActivityLog(home: scratch))
        defer { Task { await server.stop() } }

        let (data, _) = try await URLSession.shared.data(from: #require(URL(string: "http://127.0.0.1:\(port)/")))
        let html = String(decoding: data, as: UTF8.self)
        #expect(html.contains("Nothing to show yet"))
        #expect(html.contains("woodcase serve ~/Designs/banking.pen"))
        // Any file at all replaces this page, so it waits on no file in particular.
        #expect(html.contains("data-empty-file=\"\""))
    }

    @Test("GET /files/{file} is the map when the file has more than one artboard")
    func filePageIsTheMap() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/files/\(bench.fileID)")
        #expect(response.statusCode == 200)
        #expect(html.contains("id=\"v-map\""))
        #expect(!html.contains("id=\"v-stage\""), "the map is a page, not a band over a render")
        #expect(html.contains("data-artboard=\"Cnv01\""))
        // Every box is a real low-res render, not an empty rectangle.
        #expect(html.contains("/artboards/Cnv01.png?max="))
        #expect(html.contains("id=\"v-outline\""))
        #expect(html.contains("id=\"v-variables\""))
        #expect(html.contains("id=\"v-activity\""))
        #expect(html.contains("id=\"v-presence\""))
    }

    @Test("A file with one artboard lands on that artboard, not on a map of one box")
    func singleArtboardFileLandsOnItsArtboard() async throws {
        let bench = try await Bench(files: ["layout-nested.pen"])
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/files/\(bench.fileID)")
        #expect(response.statusCode == 200)
        #expect(html.contains("id=\"v-stage\""))
        #expect(html.contains("id=\"v-layout\""))
        #expect(!html.contains("id=\"v-map\""))
    }

    @Test("GET a named artboard shows that one, with no band above the render")
    func namedArtboardIsServed() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/files/\(bench.fileID)/artboards/Brd01")
        #expect(response.statusCode == 200)
        #expect(html.contains("data-artboard=\"Brd01\""))
        #expect(html.contains("id=\"v-stage\""))
        #expect(!html.contains("id=\"v-map\""), "the artboard view gives the render the whole pane")
        #expect(!html.contains("v-canvas-head"))
        #expect(!html.contains("v-map-board"))
    }

    @Test("The page route does not shadow the image endpoint it sits beside")
    func pngStillWins() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (data, response) = try await bench.bytes("/files/\(bench.fileID)/artboards/Cnv01.png")
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(response.value(forHTTPHeaderField: "X-Woodcase-Scale") != nil)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("?node= outlines the node server-side and names it in the footer")
    func selectionIsServedWithoutScript() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, _) = try await bench.get("/files/\(bench.fileID)?node=Ttl01")
        #expect(html.contains("v-box is-selected"))
        #expect(html.contains("data-node=\"Ttl01\""))
        #expect(html.contains("id=\"v-selection-path\""))
        #expect(html.contains("data-copy="))
    }

    @Test("Each fragment is exactly the element it replaces")
    func fragmentsAreOneElement() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        for fragment in [ViewerLink.Fragment.activity, .variables, .presence, .map, .artboards] {
            let (html, response) = try await bench.get(ViewerLink.fragment(fragment, file: bench.fileID))
            #expect(response.statusCode == 200, "\(fragment.rawValue) should be served")
            #expect(html.contains("id=\"\(fragment.target)\""), "\(fragment.rawValue) should carry its id")
            #expect(!html.contains("<!DOCTYPE"), "\(fragment.rawValue) should not be a whole page")
        }

        for path in [
            ViewerLink.render(file: bench.fileID, artboard: "Cnv01"),
            ViewerLink.outline(file: bench.fileID, artboard: "Cnv01"),
            ViewerLink.follow(file: bench.fileID, artboard: "Cnv01"),
            ViewerLink.follow(file: bench.fileID),
        ] {
            let (html, response) = try await bench.get(path)
            #expect(response.statusCode == 200, "\(path) should be served")
            #expect(!html.contains("<!DOCTYPE"), "\(path) should not be a whole page")
        }
    }

    @Test("The map's follow control submits to the map; an artboard's to that artboard")
    func followKnowsWhichPageItIsOn() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (map, _) = try await bench.get(ViewerLink.follow(file: bench.fileID))
        #expect(map.contains("action=\"/files/\(bench.fileID)\""))

        let (artboard, _) = try await bench.get(
            ViewerLink.follow(file: bench.fileID, artboard: "Brd01")
        )
        #expect(artboard.contains("action=\"/files/\(bench.fileID)/artboards/Brd01\""))
    }

    @Test("The map is a whole-file fragment: an artboard added while it is open joins it")
    func mapIsAFragment() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/files/\(bench.fileID)/map")
        #expect(response.statusCode == 200)
        #expect(html.contains("id=\"v-map\""))
        #expect(!html.contains("<!DOCTYPE"))
        // `data-artboard` is the hook everything hanging per-artboard state off a box
        // uses — the unread dot, the keyboard's focus ring, the follow-drop handler.
        #expect(html.contains("data-artboard=\"Brd01\""))
        // `batch.pen`'s roots sit at (0, 0), (500, 40) and (0, 400) — the map draws
        // each where the file puts it, measured from the map's own corner.
        #expect(html.contains("--v-map-w: 700; --v-map-h: 424"))
        #expect(html.contains("--v-board-x: 500; --v-board-y: 40; --v-board-w: 200; --v-board-h: 100"))
        #expect(html.contains("/artboards/Cmp01"))
    }

    @Test("The map page's outline lists the artboards, as its own fragment")
    func artboardListingIsAFragment() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/files/\(bench.fileID)/artboards")
        #expect(response.statusCode == 200)
        #expect(html.contains("id=\"v-outline\""), "it swaps into the outline's own slot")
        #expect(!html.contains("<!DOCTYPE"))
        #expect(html.contains("Artboards"))
        for id in ["Cnv01", "Brd01", "Cmp01"] {
            #expect(html.contains("data-artboard=\"\(id)\""), "\(id) should have a row")
        }
        #expect(html.contains("v-kind-component"), "the reusable root keeps its badge")
        #expect(html.contains("500,40 200×100"), "a row carries the settled rect")
    }

    @Test("A fragment renders under the same view state the page does")
    func fragmentsCarryTheViewState() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (html, _) = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01/outline?node=Ttl01")
        #expect(html.contains("is-selected"))
        // Every row selects into the artboard the fragment names, never into the map.
        #expect(html.contains("href=\"/files/\(bench.fileID)/artboards/Cnv01?node="))
    }

    @Test("The stylesheet and the script are served as themselves")
    func assetsAreServed() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (css, cssResponse) = try await bench.get("/viewer.css")
        #expect(cssResponse.value(forHTTPHeaderField: "Content-Type") == "text/css; charset=utf-8")
        #expect(css.contains("prefers-color-scheme: dark"))
        #expect(css.contains("--v-chrome: #ECEAE3"))

        let (js, jsResponse) = try await bench.get("/viewer.js")
        #expect(jsResponse.value(forHTTPHeaderField: "Content-Type") == "text/javascript; charset=utf-8")
        #expect(js.contains("new EventSource(\"/events\")"))
        #expect(js.contains("v-render-region"))
    }

    @Test("An unknown file is a 404 that says how to find the ids that exist")
    func unknownFileTeaches() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (body, response) = try await bench.get("/files/deadbeefcafe")
        #expect(response.statusCode == 404)
        #expect(body.contains("GET /files lists the id of every file"))
    }

    @Test("An unknown artboard is a 404 listing the ones the file has")
    func unknownArtboardTeaches() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (body, response) = try await bench.get("/files/\(bench.fileID)/artboards/Nope")
        #expect(response.statusCode == 404)
        #expect(body.contains("Cnv01"))
    }

    @Test("A malformed ?theme= is a 400 naming the pin, not a silently dropped axis")
    func malformedThemeTeaches() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        let (body, response) = try await bench.get("/files/\(bench.fileID)?theme=nonsense")
        #expect(response.statusCode == 400)
        #expect(body.contains("is not axis:value"))
    }

    @Test("A recent edit reaches the page as a colored row and a marker over the render")
    func recentEditsShowOnThePage() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        try await PenFileTransaction.run(at: bench.file, identity: "claude-a", log: bench.log, timeout: ViewerFixtures.lockBudget) { _, recorder in
            try recorder.apply(.updateCommon(EditOperation.UpdateCommon(
                nodeID: "Ttl01", common: PenNodeCommon(name: "Renamed")
            )))
        }

        let (html, _) = try await bench.get("/files/\(bench.fileID)/artboards/Cnv01")
        #expect(html.contains("data-editors=\"claude-a\""))
        #expect(html.contains("v-box is-edit"))
        #expect(html.contains("--v-actor: hsl(152 85% 48%)"))

        // And the map, which has no node boxes, marks the artboard the write landed in.
        let (map, _) = try await bench.get("/files/\(bench.fileID)")
        #expect(map.contains("class=\"v-map-board is-touched\" data-artboard=\"Cnv01\""))
        #expect(map.contains("--v-actor: hsl(152 85% 48%)"))
        #expect(!map.contains("data-artboard=\"Brd01\" title=\"Board\" style=\"--v-board-x: 500; --v-board-y: 40; --v-board-w: 200; --v-board-h: 100;"),
                "an artboard nobody touched carries no color")
    }

    @Test("A ?node= on the file's own URL opens the artboard that holds it, not the map")
    func aSelectedNodeBeatsTheMap() async throws {
        let bench = try await Bench()
        defer { Task { await bench.stop() } }

        // `/files/{file}?node=Vr7Kd` is the URL <doc:WoodcaseViewer> tells an agent to
        // paste, and landing it on a map that cannot show a selection would answer a
        // question nobody asked.
        let (html, response) = try await bench.get("/files/\(bench.fileID)?node=Cd201")
        #expect(response.statusCode == 200)
        #expect(html.contains("data-artboard=\"Cnv01\""), "Cd201 lives in Cnv01")
        #expect(html.contains("v-box is-selected"))
        #expect(!html.contains("id=\"v-map\""))
    }

    @Test("A file with no artboards is an empty state, not a JSON 404")
    func aFileWithNoArtboardsIsAnEmptyState() async throws {
        let bench = try await Bench(files: ["parser-variables.pen"])
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/files/\(bench.fileID)")
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
        #expect(html.contains("No artboards yet"))
        #expect(html.contains("watching for changes"))
        // It carries the file id so the stream can turn it into the map in place.
        #expect(html.contains("data-empty-file=\"\(bench.fileID)\""))
        #expect(!html.contains("cannot be rendered"))
    }

    @Test("An artboard named on a file that has none is a 404 that quotes no empty id")
    func anArtboardNamedOnAnEmptyFileTeaches() async throws {
        let bench = try await Bench(files: ["parser-variables.pen"])
        defer { Task { await bench.stop() } }

        let (body, response) = try await bench.get("/files/\(bench.fileID)/artboards/Nope")
        #expect(response.statusCode == 404)
        #expect(body.contains("has no artboards"))
        #expect(!body.contains("''"), "an error that can quote nothing chose the wrong branch")
    }

    @Test("The PNG endpoint on a file with no artboards says so without quoting nothing")
    func aPNGOfAnEmptyFileTeaches() async throws {
        let bench = try await Bench(files: ["parser-variables.pen"])
        defer { Task { await bench.stop() } }

        let (body, response) = try await bench.get("/files/\(bench.fileID)/artboards/Nope.png")
        #expect(response.statusCode == 404)
        #expect(!body.contains("''"))
    }
}
