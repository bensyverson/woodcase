//
//  PenTextRunMentionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A run's mention: it reaches the segments a renderer draws, survives storage, and
/// never changes a measured size.
struct PenTextRunMentionTests {
    @Test("A run's mention reaches the segments it covers")
    func segmentsCarryMention() {
        let segments = PenTextStyle().segments(
            of: "hi @ben", runs: [PenTextRun(start: 3, end: 7, fontWeight: 600, mention: "ben")]
        )
        #expect(segments.map(\.mention) == [nil, "ben"])
    }

    @Test("A later overlapping mention wins, as a later run's keys do")
    func laterMentionWins() {
        let segments = PenTextStyle().segments(
            of: "@a", runs: [PenTextRun(start: 0, end: 2, mention: "a"), PenTextRun(start: 0, end: 2, mention: "b")]
        )
        #expect(segments.map(\.mention) == ["b"])
    }

    @Test("A mention survives the spans' storage round trip, and a stored one that is not a name is refused")
    func wireRoundTrip() throws {
        let spans = PenTextSpans(text: "hi @ben", runs: [PenTextRun(start: 3, end: 7, mention: "ben")])
        let read = try PenTextSpans(metadataValue: spans.metadataValue)
        #expect(read == spans)
        for bad: AnyCodable in [.string(""), .int(3)] {
            let value: AnyCodable = .dictionary([
                "text": .string("hi"),
                "runs": .array([.dictionary(["start": .int(0), "end": .int(2), "mention": bad])]),
            ])
            #expect(throws: PenTextSpans.WireError.self) { try PenTextSpans(metadataValue: value) }
        }
    }

    @Test("A measurement's cache key leaves the mention out")
    func cacheKeyIgnoresMention() {
        let mentioned = PenTextMeasureRequest(text: "@ben", runs: [PenTextRun(start: 0, end: 4, fontWeight: 600, mention: "ben")])
        let plain = PenTextMeasureRequest(text: "@ben", runs: [PenTextRun(start: 0, end: 4, fontWeight: 600)])
        #expect(mentioned.ignoringColor == plain.ignoringColor)
        let onlyMention = PenTextMeasureRequest(text: "@ben", runs: [PenTextRun(start: 0, end: 4, mention: "ben")])
        #expect(onlyMention.ignoringColor.runs.isEmpty)
    }
}
