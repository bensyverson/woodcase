//
//  ViewerRoutesTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct ViewerRoutesTests {
    private func request(_ method: HTTPRequest.Method, _ path: String) -> HTTPRequest {
        HTTPRequest(method: method, path: path, query: [:], headers: [:], target: path)
    }

    /// Resolves a request against `routes` and returns the handler's body as text.
    private func text(_ routes: ViewerRoutes, _ request: HTTPRequest) async throws -> String {
        guard case let .handler(handler, parameters) = routes.match(request) else {
            Issue.record("expected a handler for \(request.path)")
            return ""
        }
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let response = try await handler(ViewerRequest(
            http: request,
            parameters: parameters,
            context: ViewerFixtures.context(files: [], home: scratch)
        ))
        guard case let .data(body) = response.body else {
            Issue.record("expected a data body")
            return ""
        }
        return String(decoding: body, as: UTF8.self)
    }

    @Test("A matched route hands back its handler and the captured parameters")
    func resolvesAHandler() async throws {
        var routes = ViewerRoutes()
        routes.add(.get, "/files/{file}") { request in
            .html("file \(request.parameters["file"] ?? "?")")
        }

        guard case let .handler(handler, parameters) = routes.match(request(.get, "/files/a1")) else {
            Issue.record("expected a handler")
            return
        }
        #expect(parameters == ["file": "a1"])

        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let response = try await handler(ViewerRequest(
            http: request(.get, "/files/a1"),
            parameters: parameters,
            context: ViewerFixtures.context(files: [], home: scratch)
        ))
        guard case let .data(body) = response.body else {
            Issue.record("expected a data body")
            return
        }
        #expect(String(decoding: body, as: UTF8.self) == "file a1")
    }

    @Test("A path no route claims resolves as not found")
    func reportsNotFound() {
        var routes = ViewerRoutes()
        routes.add(.get, "/files") { _ in .html("") }

        guard case .notFound = routes.match(request(.get, "/nope")) else {
            Issue.record("expected notFound")
            return
        }
    }

    @Test("A path that exists for another method reports the methods that are allowed")
    func reportsMethodNotAllowed() {
        var routes = ViewerRoutes()
        routes.add(.head, "/files") { _ in .html("") }

        guard case let .methodNotAllowed(allowed) = routes.match(request(.get, "/files")) else {
            Issue.record("expected methodNotAllowed")
            return
        }
        #expect(allowed == [.head])
    }

    @Test("At equal specificity the first route registered wins, so pages shadow built-ins")
    func firstRegistrationWins() async throws {
        var pages = ViewerRoutes()
        pages.add(.get, "/") { _ in .html("the page") }

        var builtIn = ViewerRoutes()
        builtIn.add(.get, "/") { _ in .html("the placeholder") }

        pages.add(contentsOf: builtIn)

        guard case let .handler(handler, _) = pages.match(request(.get, "/")) else {
            Issue.record("expected a handler")
            return
        }
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let response = try await handler(ViewerRequest(
            http: request(.get, "/"),
            parameters: [:],
            context: ViewerFixtures.context(files: [], home: scratch)
        ))
        guard case let .data(body) = response.body else {
            Issue.record("expected a data body")
            return
        }
        #expect(String(decoding: body, as: UTF8.self) == "the page")
    }

    @Test("A suffixed capture beats a bare one, however late it is registered")
    func suffixedCaptureBeatsBareCapture() async throws {
        var routes = ViewerRoutes()
        routes.add(.get, "/files/{file}/artboards/{artboard}") { _ in .html("the page") }
        routes.add(.get, "/files/{file}/artboards/{artboard}.png") { _ in .html("the image") }

        #expect(try await text(routes, request(.get, "/files/a1/artboards/Cnv01.png")) == "the image")
        #expect(try await text(routes, request(.get, "/files/a1/artboards/Cnv01")) == "the page")
    }

    @Test("A literal segment beats a capture, however late it is registered")
    func literalBeatsCapture() async throws {
        var routes = ViewerRoutes()
        routes.add(.get, "/files/{file}") { _ in .html("the file") }
        routes.add(.get, "/files/index") { _ in .html("the index") }

        #expect(try await text(routes, request(.get, "/files/index")) == "the index")
        #expect(try await text(routes, request(.get, "/files/a1")) == "the file")
    }

    @Test("The first segment that differs decides, not the count of literals")
    func theFirstDifferingSegmentDecides() async throws {
        var routes = ViewerRoutes()
        routes.add(.get, "/{section}/tree/leaf") { _ in .html("the section") }
        routes.add(.get, "/files/{a}/{b}") { _ in .html("the file") }

        #expect(try await text(routes, request(.get, "/files/tree/leaf")) == "the file")
    }

    @Test("Registration order breaks a tie between two patterns of the same shape")
    func registrationOrderBreaksTies() async throws {
        var routes = ViewerRoutes()
        routes.add(.get, "/files/{file}") { _ in .html("first") }
        routes.add(.get, "/files/{other}") { _ in .html("second") }

        #expect(try await text(routes, request(.get, "/files/a1")) == "first")
    }

    @Test("A GET route answers HEAD too, so a probe never gets a spurious 405")
    func getServesHead() {
        var routes = ViewerRoutes()
        routes.add(.get, "/files") { _ in .html("") }

        guard case .handler = routes.match(request(.head, "/files")) else {
            Issue.record("expected the GET handler to serve HEAD")
            return
        }
    }
}
