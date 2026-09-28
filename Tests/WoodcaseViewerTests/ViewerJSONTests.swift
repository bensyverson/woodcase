//
//  ViewerJSONTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct ViewerJSONTests {
    private struct Moment: Codable, Equatable {
        let when: Date
        let what: String
    }

    /// An instant whose millisecond is exactly representable as a `Double`, so the test
    /// is about the format rather than about binary floating point.
    private let instant = Date(timeIntervalSince1970: 1_756_484_264.125)

    @Test("Times are written in the activity log's ISO-8601 form, to the millisecond")
    func writesLogTimes() throws {
        let json = try ViewerJSON.text(Moment(when: instant, what: "set"))
        #expect(json.contains("\"when\" : \"2025-08-29T"))
        #expect(json.contains(".125Z\""))
    }

    @Test("The decoder reads back exactly what the encoder wrote")
    func roundTrips() throws {
        let moment = Moment(when: instant, what: "set")
        let data = try ViewerJSON.encoder.encode(moment)
        #expect(try ViewerJSON.decoder.decode(Moment.self, from: data) == moment)
    }

    @Test("A time finer than a millisecond is rounded, as the activity log rounds its own")
    func roundsToMilliseconds() {
        let fine = Date(timeIntervalSince1970: 1_756_484_264.1256)
        #expect(ViewerJSON.roundedToMilliseconds(fine)
            .timeIntervalSince1970 == 1_756_484_264.126)
    }

    @Test("Keys are sorted and slashes unescaped, so a body is stable and readable")
    func writesStableReadableJSON() throws {
        struct Payload: Encodable { let path: String; let name: String }
        let json = try ViewerJSON.text(Payload(path: "/tmp/a.pen", name: "a"))
        #expect(json.contains("\"/tmp/a.pen\""))
        #expect(try #require(json.range(of: "\"name\"")?.lowerBound) < json.range(of: "\"path\"")!.lowerBound)
    }

    @Test("A time that is not the log's form fails with a message naming the value")
    func rejectsAnUnknownTimeFormat() {
        let data = Data("{\"what\":\"set\",\"when\":\"yesterday\"}".utf8)
        #expect(throws: DecodingError.self) {
            try ViewerJSON.decoder.decode(Moment.self, from: data)
        }
    }
}
