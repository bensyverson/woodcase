//
//  RelativeAgeTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

/// The two age spellings the page uses: the compact one that fits a table column and
/// the long one a file row reads as a sentence.
struct RelativeAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func compact(_ seconds: TimeInterval) -> String {
        RelativeAge.text(from: now.addingTimeInterval(-seconds), to: now, style: .compact)
    }

    private func long(_ seconds: TimeInterval) -> String {
        RelativeAge.text(from: now.addingTimeInterval(-seconds), to: now, style: .long)
    }

    @Test("Compact ages are one number and one unit")
    func compactIsTerse() {
        #expect(compact(4) == "4s")
        #expect(compact(59) == "59s")
        #expect(compact(60) == "1m")
        #expect(compact(9 * 60) == "9m")
        #expect(compact(3600) == "1h")
        #expect(compact(26 * 3600) == "1d")
        #expect(compact(2 * 86400) == "2d")
    }

    @Test("Long ages read as a sentence fragment")
    func longReadsAsProse() {
        #expect(long(2) == "just now")
        #expect(long(45) == "45 s ago")
        #expect(long(120) == "2 min ago")
        #expect(long(18 * 60) == "18 min ago")
        #expect(long(3600) == "1 h ago")
        #expect(long(30 * 3600) == "yesterday")
        #expect(long(4 * 86400) == "4 days ago")
    }

    @Test("A time in the future is zero, not a negative age")
    func futureIsZero() {
        #expect(RelativeAge.text(from: now.addingTimeInterval(30), to: now, style: .compact) == "0s")
        #expect(RelativeAge.text(from: now.addingTimeInterval(30), to: now, style: .long) == "just now")
    }

    @Test("Recency is the 30-second window the outline colours rows by")
    func recencyWindow() {
        #expect(RelativeAge.isRecent(now.addingTimeInterval(-29), now: now))
        #expect(!RelativeAge.isRecent(now.addingTimeInterval(-31), now: now))
    }
}
