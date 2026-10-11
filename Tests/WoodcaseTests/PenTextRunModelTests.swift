//
//  PenTextRunModelTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The span model as RapidPro and Penumbra see it — imported without `@testable`, so these
/// fail to compile if ``PenTextRun``, ``PenTextSpans`` or ``PenTextSegment`` stop being
/// public.
struct PenTextRunModelTests {
    private static let base = PenTextStyle(fontFamily: "Inter", fontSize: 14)

    @Test("A run's range is its start up to its end, in UTF-16 code units")
    func runRange() {
        let run = PenTextRun(start: 2, end: 5, fontWeight: 700)
        #expect(run.range == 2 ..< 5)
    }

    @Test("Spans made for the content apply their runs")
    func matchingSpansApply() {
        let runs = [PenTextRun(start: 0, end: 4, fontWeight: 700)]
        let spans = PenTextSpans(text: "Bold text", runs: runs)
        #expect(spans.appliedRuns(to: "Bold text") == runs)
        #expect(!spans.isStale(for: "Bold text"))
    }

    @Test("Spans made for other content are stale and apply no runs")
    func staleSpansApplyNothing() {
        let spans = PenTextSpans(text: "Bold text", runs: [PenTextRun(start: 0, end: 4, fontWeight: 700)])
        #expect(spans.appliedRuns(to: "Bold text, edited in Pen") == [])
        #expect(spans.isStale(for: "Bold text, edited in Pen"))
    }

    @Test("Content equal only by Unicode equivalence is stale: its UTF-16 offsets differ")
    func staleAcrossNormalization() {
        // "é" decomposed (e + combining acute, 2 units) against precomposed (1 unit).
        let spans = PenTextSpans(text: "cafe\u{301} au lait", runs: [PenTextRun(start: 6, end: 8, isItalic: true)])
        #expect(spans.isStale(for: "caf\u{E9} au lait"))
        #expect(spans.appliedRuns(to: "caf\u{E9} au lait").isEmpty)
    }

    @Test("A run overrides only the keys it sets")
    func applyingOverridesSetKeys() {
        let run = PenTextRun(start: 0, end: 1, fontSize: 28, fontWeight: 700, isItalic: true, underline: true)
        let styled = Self.base.applying(run)
        #expect(styled.fontFamily == "Inter")
        #expect(styled.fontSize == 28)
        #expect(styled.fontWeight == 700)
        #expect(styled.isItalic)
        #expect(styled.underline)
        #expect(!styled.strikethrough)
        #expect(styled.lineHeight == Self.base.lineHeight)
        #expect(styled.textAlign == Self.base.textAlign)
    }

    @Test("A run can turn a node's decoration or italic off")
    func applyingCanClear() {
        let node = PenTextStyle(isItalic: true, underline: true, strikethrough: true)
        let run = PenTextRun(start: 0, end: 1, isItalic: false, underline: false, strikethrough: false)
        let styled = node.applying(run)
        #expect(!styled.isItalic)
        #expect(!styled.underline)
        #expect(!styled.strikethrough)
    }

    @Test("Segments partition the text; unstyled ranges keep the node's style")
    func segmentsPartition() throws {
        let segments = Self.base.segments(of: "Make this bold", runs: [PenTextRun(start: 10, end: 14, fontWeight: 700)])
        try #require(segments.map(\.range) == [0 ..< 10, 10 ..< 14])
        #expect(segments[0].style == Self.base)
        #expect(segments[0].fill == nil)
        #expect(segments[1].style.fontWeight == 700)
    }

    @Test("A text without runs is one segment in the node's style; an empty text has none")
    func segmentsWithoutRuns() {
        let segments = Self.base.segments(of: "Plain", runs: [])
        #expect(segments == [PenTextSegment(range: 0 ..< 5, style: Self.base, fill: nil)])
        #expect(Self.base.segments(of: "", runs: [PenTextRun(start: 0, end: 3, fontWeight: 700)]).isEmpty)
    }

    @Test("Where runs overlap, the later run wins for the keys it sets")
    func overlapLaterWins() throws {
        let red = PenHexColor(red: 255, green: 0, blue: 0)
        let blue = PenHexColor(red: 0, green: 0, blue: 255)
        let segments = Self.base.segments(of: "abcdef", runs: [
            PenTextRun(start: 0, end: 4, fontWeight: 700, fill: red),
            PenTextRun(start: 2, end: 6, isItalic: true, fill: blue),
        ])
        try #require(segments.map(\.range) == [0 ..< 2, 2 ..< 4, 4 ..< 6])
        #expect(segments[0].style.fontWeight == 700 && !segments[0].style.isItalic && segments[0].fill == red)
        #expect(segments[1].style.fontWeight == 700 && segments[1].style.isItalic && segments[1].fill == blue)
        #expect(segments[2].style.fontWeight == 400 && segments[2].style.isItalic && segments[2].fill == blue)
    }

    @Test("Runs are clamped to the text; empty and inverted runs are ignored")
    func clampedAndIgnored() throws {
        let segments = Self.base.segments(of: "abc", runs: [
            PenTextRun(start: -4, end: 1, fontWeight: 700),
            PenTextRun(start: 2, end: 99, isItalic: true),
            PenTextRun(start: 1, end: 1, fontSize: 40),
            PenTextRun(start: 2, end: 1, fontSize: 40),
        ])
        try #require(segments.map(\.range) == [0 ..< 1, 1 ..< 2, 2 ..< 3])
        #expect(segments[0].style.fontWeight == 700)
        #expect(segments[1].style == Self.base)
        #expect(segments[2].style.isItalic)
        #expect(segments.allSatisfy { $0.style.fontSize == 14 })
    }

    @Test("A run edge inside a grapheme cluster widens the run to the whole cluster")
    func snapsToGraphemes() throws {
        // "a👍🏽b": a (0..<1), the toned thumbs-up (1..<5, four UTF-16 units), b (5..<6).
        let text = "a👍🏽b"
        let segments = Self.base.segments(of: text, runs: [PenTextRun(start: 2, end: 3, fontWeight: 700)])
        try #require(segments.map(\.range) == [0 ..< 1, 1 ..< 5, 5 ..< 6])
        #expect(segments[1].style.fontWeight == 700)
    }

    @Test("The style at an index is its segment's")
    func styleAtIndex() {
        let segments = Self.base.segments(of: "Make this bold", runs: [PenTextRun(start: 10, end: 14, fontWeight: 700)])
        #expect(segments.first { $0.range.contains(11) }?.style.fontWeight == 700)
        #expect(segments.first { $0.range.contains(3) }?.style.fontWeight == 400)
    }
}
