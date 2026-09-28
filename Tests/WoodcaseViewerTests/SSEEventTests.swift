//
//  SSEEventTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct SSEEventTests {
    @Test("An event is an id line, an event line, a data line and a blank line")
    func serializesOneEvent() {
        let event = SSEEvent(id: 7, name: .change, data: "{\"file\":\"a1\"}")
        #expect(event.wireFormat == "id: 7\nevent: change\ndata: {\"file\":\"a1\"}\n\n")
    }

    @Test("Multi-line data becomes one data line per line, as the format requires")
    func splitsMultilineData() {
        let event = SSEEvent(id: 1, name: .presence, data: "{\n  \"a\": 1\n}")
        #expect(event.wireFormat == "id: 1\nevent: presence\ndata: {\ndata:   \"a\": 1\ndata: }\n\n")
    }

    @Test("The heartbeat is a comment, so a client parses nothing from it")
    func heartbeatIsAComment() {
        #expect(SSEEvent.heartbeat == ": heartbeat\n\n")
    }

    @Test("Event names are the two the viewer publishes")
    func namesAreTyped() {
        #expect(SSEEvent.Name.change.rawValue == "change")
        #expect(SSEEvent.Name.presence.rawValue == "presence")
        #expect(SSEEvent.Name.allCases.count == 2)
    }

    @Test("An encodable payload becomes an event with JSON data")
    func encodesAPayload() throws {
        struct Payload: Encodable { let file: String }
        let event = try SSEEvent(id: 3, name: .change, payload: Payload(file: "a1"))
        #expect(event.data.contains("\"file\""))
        #expect(event.wireFormat.hasPrefix("id: 3\nevent: change\ndata: "))
    }
}
