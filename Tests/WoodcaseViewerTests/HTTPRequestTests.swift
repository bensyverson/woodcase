//
//  HTTPRequestTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct HTTPRequestTests {
    @Test("Parses the request line into method, path and version-independent target")
    func parsesRequestLine() throws {
        let request = try HTTPRequest.parse(head: "GET /files HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(request.method == .get)
        #expect(request.path == "/files")
        #expect(request.target == "/files")
        #expect(request.query.isEmpty)
    }

    @Test("Splits the query string and percent-decodes both halves")
    func parsesQuery() throws {
        let head = "GET /files/a1/tree.json?node=Card%2FTitle&depth=2&expand HTTP/1.1\r\n\r\n"
        let request = try HTTPRequest.parse(head: head)
        #expect(request.path == "/files/a1/tree.json")
        #expect(request.query["node"] == "Card/Title")
        #expect(request.query["depth"] == "2")
        // A bare key is present with an empty value, so `?expand` reads as a flag.
        #expect(request.query["expand"] == "")
    }

    @Test("Percent-decodes the path and turns + into a space in query values")
    func decodesPathAndPlus() throws {
        let request = try HTTPRequest.parse(head: "GET /files/a1/artboards/Frame%2001.png?theme=Mode:Dark+Blue HTTP/1.1\r\n\r\n")
        #expect(request.path == "/files/a1/artboards/Frame 01.png")
        #expect(request.query["theme"] == "Mode:Dark Blue")
    }

    @Test("Each segment is decoded on its own, so an encoded slash stays inside one id")
    func decodesSegmentsIndependently() throws {
        let request = try HTTPRequest.parse(head: "GET /files/a1/artboards/YGJ0d%2FnSNTs.png HTTP/1.1\r\n\r\n")
        #expect(request.segments == ["files", "a1", "artboards", "YGJ0d/nSNTs.png"])
        #expect(Route(.get, "/files/{file}/artboards/{artboard}.png")
            .match(segments: request.segments) == ["file": "a1", "artboard": "YGJ0d/nSNTs"])
    }

    @Test("Header names are matched case-insensitively")
    func lowercasesHeaderNames() throws {
        let head = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nAccept: text/html\r\nUser-Agent: probe\r\n\r\n"
        let request = try HTTPRequest.parse(head: head)
        #expect(request.headers["host"] == "localhost:8080")
        #expect(request.header("ACCEPT") == "text/html")
        #expect(request.header("user-agent") == "probe")
    }

    @Test("An empty or truncated head is a malformed request, not a crash")
    func rejectsMalformedHead() {
        #expect(throws: HTTPRequest.ParseError.self) {
            try HTTPRequest.parse(head: "")
        }
        #expect(throws: HTTPRequest.ParseError.self) {
            try HTTPRequest.parse(head: "GET\r\n\r\n")
        }
    }

    @Test("A method the viewer does not serve is named in the error, so the reply can be 405")
    func namesUnsupportedMethod() {
        #expect(throws: HTTPRequest.ParseError.unsupportedMethod("TRACE")) {
            try HTTPRequest.parse(head: "TRACE / HTTP/1.1\r\n\r\n")
        }
    }

    @Test("HEAD is parsed, so a probe gets headers without a body")
    func parsesHead() throws {
        let request = try HTTPRequest.parse(head: "HEAD /files HTTP/1.1\r\n\r\n")
        #expect(request.method == .head)
    }

    @Test("The head is complete only once a blank line has arrived")
    func findsEndOfHead() {
        let partial = Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)
        #expect(HTTPRequest.headLength(in: partial) == nil)

        let complete = Data("GET / HTTP/1.1\r\nHost: x\r\n\r\nBODY".utf8)
        #expect(HTTPRequest.headLength(in: complete) == Data("GET / HTTP/1.1\r\nHost: x".utf8).count)
    }
}
