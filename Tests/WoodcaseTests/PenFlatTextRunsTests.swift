//
//  PenFlatTextRunsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The runs of a text kept flat (``PenFlatTextRuns``): flattened from a file's possibly
/// overlapping runs, read back by index and by range, and shifted by each edit of the
/// text, so spans written from them always fit it.
struct PenFlatTextRunsTests {
    private typealias Run = PenTextRun

    // MARK: Flattening

    @Test("overlapping runs flatten so a later run wins only for the keys it sets")
    func overlapsFlatten() {
        let runs = PenFlatTextRuns([
            Run(start: 0, end: 6, fontWeight: 700),
            Run(start: 3, end: 9, isItalic: true),
        ], length: 10)

        #expect(runs.runs == [
            Run(start: 0, end: 3, fontWeight: 700),
            Run(start: 3, end: 6, fontWeight: 700, isItalic: true),
            Run(start: 6, end: 9, isItalic: true),
        ])
    }

    @Test("a later run wins for a key both set, and every key flattens — the padding and the mention too")
    func laterRunWinsForEveryKey() {
        let runs = PenFlatTextRuns([
            PenTextRunKeysTests.everyKey.over(0 ..< 4),
            Run(start: 2, end: 4, fontWeight: 300),
        ], length: 4)

        var overlap = PenTextRunKeysTests.everyKey.over(2 ..< 4)
        overlap.fontWeight = 300
        #expect(runs.runs == [PenTextRunKeysTests.everyKey.over(0 ..< 2), overlap])
    }

    @Test("adjacent runs with the same keys merge, and runs that set nothing drop")
    func mergeAndDrop() {
        let runs = PenFlatTextRuns([
            Run(start: 0, end: 2, fontWeight: 700),
            Run(start: 2, end: 5, fontWeight: 700),
            Run(start: 6, end: 8),
        ], length: 10)

        #expect(runs.runs == [Run(start: 0, end: 5, fontWeight: 700)])
    }

    @Test("runs are clamped to the text, and inverted or out-of-range runs drop")
    func clamped() {
        let runs = PenFlatTextRuns([
            Run(start: 4, end: 40, underline: true),
            Run(start: -3, end: 1, isItalic: true),
            Run(start: 5, end: 2, fontWeight: 700),
            Run(start: 9, end: 12, strikethrough: true),
        ], length: 6)

        #expect(runs.runs == [Run(start: 0, end: 1, isItalic: true), Run(start: 4, end: 6, underline: true)])
        #expect(runs.length == 6)
    }

    @Test("runs given out of order come back sorted")
    func sorted() {
        let runs = PenFlatTextRuns([Run(start: 5, end: 6, underline: true), Run(start: 0, end: 2, isItalic: true)], length: 6)

        #expect(runs.runs.map(\.start) == [0, 5])
        #expect(!runs.isEmpty)
        #expect(PenFlatTextRuns(length: 3).isEmpty)
    }

    // MARK: Reading

    @Test("the keys at an index are the run covering it, offsets zeroed, or none")
    func keysAtIndex() {
        let runs = PenFlatTextRuns([Run(start: 2, end: 4, fontWeight: 700)], length: 6)

        #expect(runs.keys(at: 2) == Run(start: 0, end: 0, fontWeight: 700))
        #expect(runs.keys(at: 3) == Run(start: 0, end: 0, fontWeight: 700))
        #expect(runs.keys(at: 4) == .noKeys)
        #expect(runs.keys(at: 0) == .noKeys)
    }

    @Test("the stretches of a range cover it whole, gaps with no keys")
    func stretches() {
        let runs = PenFlatTextRuns([Run(start: 2, end: 4, fontWeight: 700), Run(start: 6, end: 8, isItalic: true)], length: 10)

        #expect(runs.stretches(in: 1 ..< 7) == [
            Run(start: 1, end: 2),
            Run(start: 2, end: 4, fontWeight: 700),
            Run(start: 4, end: 6),
            Run(start: 6, end: 7, isItalic: true),
        ])
        #expect(runs.stretches(in: 8 ..< 10) == [Run(start: 8, end: 10)])
        #expect(runs.stretches(in: 3 ..< 3).isEmpty)
    }

    // MARK: Spans

    @Test("runs read from spans that fit the content are flattened; stale or no spans give none")
    func fromSpans() {
        let spans = PenTextSpans(text: "Make bold", runs: [Run(start: 5, end: 9, fontWeight: 700)])

        #expect(PenFlatTextRuns(spans: spans, content: "Make bold").runs == spans.runs)
        let stale = PenFlatTextRuns(spans: spans, content: "Make it bold")
        #expect(stale.isEmpty)
        #expect(stale.length == "Make it bold".utf16.count)
        #expect(PenFlatTextRuns(spans: nil, content: "👍🏽 hi").length == 7)
    }

    @Test("spans for a text hold its runs, or are nil when no run is left")
    func toSpans() {
        let runs = PenFlatTextRuns([Run(start: 0, end: 2, underline: true)], length: 4)

        #expect(runs.spans(for: "abcd") == PenTextSpans(text: "abcd", runs: [Run(start: 0, end: 2, underline: true)]))
        #expect(PenFlatTextRuns(length: 4).spans(for: "abcd") == nil)
    }

    @Test("stale spans are replaced by fresh ones for the current content, which then take a format")
    func staleSpansAreReplaced() {
        let stale = PenTextSpans(text: "old words", runs: [Run(start: 0, end: 3, isItalic: true)])
        var runs = PenFlatTextRuns(spans: stale, content: "new text")

        runs.set(Run(start: 0, end: 0, fontWeight: 700), over: 0 ..< 3)

        #expect(runs.spans(for: "new text") == PenTextSpans(text: "new text", runs: [Run(start: 0, end: 3, fontWeight: 700)]))
        #expect(runs.spans(for: "new text")?.isStale(for: "new text") == false)
    }
}
