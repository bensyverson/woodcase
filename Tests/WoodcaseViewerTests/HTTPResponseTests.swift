//
//  HTTPResponseTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct HTTPResponseTests {
    @Test("A data response serializes a status line, content type, length and close")
    func serializesHead() {
        let response = HTTPResponse.html("<p>hi</p>")
        let head = String(decoding: response.headData(), as: UTF8.self)

        #expect(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(head.contains("Content-Type: text/html; charset=utf-8\r\n"))
        #expect(head.contains("Content-Length: 9\r\n"))
        #expect(head.contains("Connection: close\r\n"))
        #expect(head.hasSuffix("\r\n\r\n"))
    }

    @Test("Every status carries the reason phrase its code is known by")
    func namesStatusReasons() {
        #expect(HTTPResponse.Status.ok.reason == "OK")
        #expect(HTTPResponse.Status.notFound.reason == "Not Found")
        #expect(HTTPResponse.Status.badRequest.reason == "Bad Request")
        #expect(HTTPResponse.Status.methodNotAllowed.reason == "Method Not Allowed")
        #expect(HTTPResponse.Status.internalServerError.reason == "Internal Server Error")
    }

    @Test("A JSON value is encoded with sorted keys so the bytes are stable")
    func encodesJSON() throws {
        struct Payload: Encodable { let b: Int; let a: Int }
        let response = try HTTPResponse.json(Payload(b: 2, a: 1))

        guard case let .data(body) = response.body else {
            Issue.record("expected a data body")
            return
        }
        #expect(String(decoding: body, as: UTF8.self).contains("\"a\" : 1"))
        #expect(response.headers["Content-Type"] == "application/json; charset=utf-8")
    }

    @Test("A PNG response is served as image/png with its byte count")
    func servesPNG() {
        let response = HTTPResponse.png(Data(repeating: 0x89, count: 42))
        #expect(response.headers["Content-Type"] == "image/png")
        let head = String(decoding: response.headData(), as: UTF8.self)
        #expect(head.contains("Content-Length: 42\r\n"))
    }

    @Test("An event-stream response asks intermediaries not to buffer and stays open")
    func opensEventStream() {
        let response = HTTPResponse.eventStream()
        #expect(response.headers["Content-Type"] == "text/event-stream")
        #expect(response.headers["Cache-Control"] == "no-cache")
        #expect(response.headers["Transfer-Encoding"] == "chunked")
        guard case .eventStream = response.body else {
            Issue.record("expected an event-stream body")
            return
        }
        let head = String(decoding: response.headData(), as: UTF8.self)
        #expect(!head.contains("Content-Length"))
        #expect(head.contains("Connection: keep-alive\r\n"))
    }

    @Test("An error response says what happened and what to do next, as JSON")
    func explainsErrors() {
        let response = HTTPResponse.failure(
            .notFound,
            message: "No file has id 'zzz'.",
            remedy: "GET /files lists the ids this server is watching."
        )
        #expect(response.status == .notFound)
        guard case let .data(body) = response.body else {
            Issue.record("expected a data body")
            return
        }
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("No file has id 'zzz'."))
        #expect(text.contains("GET /files lists the ids"))
    }
}
