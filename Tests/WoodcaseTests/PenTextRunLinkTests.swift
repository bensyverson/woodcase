//
//  PenTextRunLinkTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A run's link (``PenTextRun/link``): stored as `link` in `metadata.woodcase.spans`, moved
/// by the flat runs an editor keeps, and never a size (leaf 69moYq).
struct PenTextRunLinkTests {
    private static let url = "https://example.com/docs"

    @Test("A link survives the spans' storage round trip as a link key")
    func wireRoundTrip() throws {
        let spans = PenTextSpans(text: "read the docs", runs: [PenTextRun(start: 9, end: 13, link: Self.url)])
        guard case let .dictionary(stored) = spans.metadataValue,
              case let .array(runs)? = stored["runs"],
              case let .dictionary(run)? = runs.first
        else {
            Issue.record("not the stored form: \(spans.metadataValue)")
            return
        }
        #expect(run["link"] == .string(Self.url))
        #expect(try PenTextSpans(metadataValue: spans.metadataValue) == spans)
    }

    @Test("A stored link that is not a URL string is refused", arguments: [AnyCodable.string(""), .int(3), .bool(true)])
    func badLinkRefused(link: AnyCodable) {
        let value: AnyCodable = .dictionary([
            "text": .string("hi"),
            "runs": .array([.dictionary(["start": .int(0), "end": .int(2), "link": link])]),
        ])
        let error = #expect(throws: PenTextSpans.WireError.self) { try PenTextSpans(metadataValue: value) }
        #expect(error?.reason == "run 1 has a link that is not a URL")
    }

    @Test("Linking a range of flat runs sets it there alone, and clearing it unlinks")
    func flatSetAndClear() {
        var runs = PenFlatTextRuns(length: 13)
        runs.set(PenTextRun(start: 0, end: 0, fontWeight: 700), over: 0 ..< 13)
        runs.set(PenTextRun(start: 0, end: 0, link: Self.url), over: 9 ..< 13)

        #expect(runs.keys(at: 10) == PenTextRun(start: 0, end: 0, fontWeight: 700, link: Self.url))
        #expect(runs.keys(at: 2) == PenTextRun(start: 0, end: 0, fontWeight: 700))

        runs.clear(.link, over: 9 ..< 13)
        #expect(runs.runs == [PenTextRun(start: 0, end: 13, fontWeight: 700)])
    }

    @Test("Neighbors linking to different URLs stay apart; the same URL merges")
    func flatMerge() {
        let other = "https://example.com/other"
        let apart = PenFlatTextRuns([
            PenTextRun(start: 0, end: 4, link: Self.url), PenTextRun(start: 4, end: 8, link: other),
        ], length: 8)
        #expect(apart.runs.count == 2)

        let merged = PenFlatTextRuns([
            PenTextRun(start: 0, end: 4, link: Self.url), PenTextRun(start: 4, end: 8, link: Self.url),
        ], length: 8)
        #expect(merged.runs == [PenTextRun(start: 0, end: 8, link: Self.url)])
    }

    @Test("A measurement's cache key leaves the link out")
    func cacheKeyIgnoresLink() {
        let linked = PenTextMeasureRequest(text: "docs", runs: [PenTextRun(start: 0, end: 4, fontWeight: 600, link: Self.url)])
        let plain = PenTextMeasureRequest(text: "docs", runs: [PenTextRun(start: 0, end: 4, fontWeight: 600)])
        #expect(linked.ignoringColor == plain.ignoringColor)
        let onlyLink = PenTextMeasureRequest(text: "docs", runs: [PenTextRun(start: 0, end: 4, link: Self.url)])
        #expect(onlyLink.ignoringColor.runs.isEmpty)
    }
}
