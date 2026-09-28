//
//  PreviewRoutesTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The three `/preview` routes, driven over a real socket.
///
/// Two benches, because the criterion is that *both* verbs answer them: one server
/// started the way `woodcase serve` starts it (a file, a log) and one started the way
/// `woodcase preview` does (no files, no log at all). The handlers are pure functions
/// of ``PreviewCatalog/all`` — they read no file, no log and no cache — so the two
/// must answer identically.
///
/// Serialized for the same reason ``ViewerPagesTests`` is: every case binds a socket.
@Suite(.serialized, .hangGuard)
struct PreviewRoutesTests {
    /// A running server with the page routes registered.
    private struct Bench {
        let scratch: URL?
        let server: ViewerServer
        let port: UInt16
        let session: URLSession

        /// The `preview` shape: no files, no logs, nothing on disk.
        static func empty() async throws -> Bench {
            let server = ViewerServer(pages: { _ in ViewerPages.routes() })
            let port = try await server.start(files: [], port: 0, logs: [])
            return Bench(scratch: nil, server: server, port: port)
        }

        /// The `serve` shape: one watched file and its project log.
        static func serving() async throws -> Bench {
            let scratch = try ViewerFixtures.scratch()
            let file = try ViewerFixtures.copy("batch.pen", into: scratch)
            let server = ViewerServer(pages: { _ in ViewerPages.routes() })
            let port = try await server.start(files: [file], port: 0, log: ActivityLog(home: scratch))
            return Bench(scratch: scratch, server: server, port: port)
        }

        private init(scratch: URL?, server: ViewerServer, port: UInt16) {
            self.scratch = scratch
            self.server = server
            self.port = port
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = ViewerFixtures.requestBudget
            session = URLSession(configuration: configuration)
        }

        func get(_ path: String) async throws -> (String, HTTPURLResponse) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            return (String(decoding: data, as: UTF8.self), response as! HTTPURLResponse)
        }

        func stop() async {
            await server.stop()
            session.invalidateAndCancel()
            if let scratch {
                try? FileManager.default.removeItem(at: scratch)
            }
        }
    }

    /// A component with at least one framed (non-page) state, for the cases that need
    /// markup nested inside a canvas.
    private static var framed: PreviewComponent {
        PreviewCatalog.all.first { component in
            component.states.contains { $0.frame != .page }
        }!
    }

    /// A component whose first state is a whole page.
    private static var whole: PreviewComponent {
        PreviewCatalog.all.first { component in
            component.states.contains { $0.frame == .page }
        }!
    }

    @Test("GET /preview lists every component in the catalog, with a link to its canvas")
    func indexListsEveryComponent() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/preview")
        #expect(response.statusCode == 200)
        #expect(html.hasPrefix("<!DOCTYPE html>"))

        for component in PreviewCatalog.all {
            #expect(html.contains(ViewerLink.previewComponent(component.slug)), "\(component.slug) has no link")
            #expect(html.contains(component.title), "\(component.slug) has no title")
            #expect(html.contains(component.source), "\(component.slug) has no source path")
        }
    }

    @Test("A server started the way `serve` starts it answers /preview too")
    func serveAnswersPreview() async throws {
        let bench = try await Bench.serving()
        defer { Task { await bench.stop() } }

        let (html, response) = try await bench.get("/preview")
        #expect(response.statusCode == 200)
        #expect(html.contains(ViewerLink.previewComponent(PreviewCatalog.all[0].slug)))
    }

    @Test("GET /preview/{component} stacks every state with its note, its anchor and its own link")
    func canvasStacksEveryState() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let component = Self.framed
        let (html, response) = try await bench.get(ViewerLink.previewComponent(component.slug))
        #expect(response.statusCode == 200)
        #expect(html.contains(PreviewProse(component.blurb).render()))

        for state in component.states {
            #expect(html.contains("id=\"\(state.slug)\""), "\(state.slug) has no anchor")
            #expect(html.contains(state.name), "\(state.slug) has no heading")
            #expect(html.contains(PreviewProse(state.note).render()), "\(state.slug) has no note")
            #expect(
                html.contains(ViewerLink.previewState(component: component.slug, state: state.slug)),
                "\(state.slug) has no link to its own page"
            )
            guard state.frame != .page else { continue }
            #expect(
                html.contains("data-frame=\"\(state.frame.rawValue)\""),
                "\(state.slug) is not in its frame"
            )
            #expect(html.contains(state.render()), "\(state.slug)'s markup is not on the canvas")
        }
    }

    @Test("A whole-page state is linked from the canvas, never nested inside it")
    func canvasLinksWholePagesRatherThanNestingThem() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let component = Self.whole
        let state = try #require(component.states.first { $0.frame == .page })
        let (html, _) = try await bench.get(ViewerLink.previewComponent(component.slug))

        #expect(html.contains(ViewerLink.previewState(component: component.slug, state: state.slug)))
        // One document per page: the canvas is itself a document, so a nested one would
        // be a second <body> in the same response.
        #expect(html.components(separatedBy: "<body").count == 2)
    }

    @Test("GET /preview/{component}/{state} is the state's own markup, byte for byte")
    func statePageCarriesTheStateVerbatim() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let component = Self.framed
        let state = try #require(component.states.first { $0.frame != .page })
        let (html, response) = try await bench.get(
            ViewerLink.previewState(component: component.slug, state: state.slug)
        )

        #expect(response.statusCode == 200)
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains(state.render()))
        #expect(html.contains("data-frame=\"\(state.frame.rawValue)\""))
        #expect(html.contains(PreviewProse(state.note).render()))
    }

    @Test("A whole-page state is served whole on its own route: its own document, nothing around it")
    func wholePageStateIsServedWhole() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let component = Self.whole
        let state = try #require(component.states.first { $0.frame == .page })
        let (html, response) = try await bench.get(
            ViewerLink.previewState(component: component.slug, state: state.slug)
        )

        #expect(response.statusCode == 200)
        #expect(html == state.render())
    }

    @Test("An unknown component is 404 naming the components that do exist")
    func unknownComponentNamesTheAlternatives() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let (body, response) = try await bench.get("/preview/avatr")
        #expect(response.statusCode == 404)
        #expect(body.contains("avatr"))
        for component in PreviewCatalog.all {
            #expect(body.contains(component.slug), "the 404 does not name \(component.slug)")
        }
        #expect(body.contains("/preview"))
    }

    @Test("An unknown state is 404 naming the states that component does have")
    func unknownStateNamesTheAlternatives() async throws {
        let bench = try await Bench.empty()
        defer { Task { await bench.stop() } }

        let component = Self.framed
        let (body, response) = try await bench.get("\(ViewerLink.previewComponent(component.slug))/nope")
        #expect(response.statusCode == 404)
        #expect(body.contains("nope"))
        for state in component.states {
            #expect(body.contains(state.slug), "the 404 does not name \(state.slug)")
        }
        #expect(body.contains(ViewerLink.previewComponent(component.slug)))
    }

    @Test("The handlers read nothing but the catalog, so the pages are the same with or without files")
    func theSamePagesEitherWay() async throws {
        let empty = try await Bench.empty()
        defer { Task { await empty.stop() } }
        let serving = try await Bench.serving()
        defer { Task { await serving.stop() } }

        let component = Self.framed
        let (fromEmpty, _) = try await empty.get(ViewerLink.previewComponent(component.slug))
        let (fromServing, _) = try await serving.get(ViewerLink.previewComponent(component.slug))
        #expect(fromEmpty == fromServing)
    }
}
