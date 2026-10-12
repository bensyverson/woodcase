//
//  PenTextRunKeysTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A run's style keys apart from its offsets (``PenTextRun/StyleKey``): enumerated once,
/// so overlaying, clearing and comparing cover every key the type holds — and a property
/// added to ``PenTextRun`` without a key fails here.
struct PenTextRunKeysTests {
    /// A run that sets every key, each to a value other than its default.
    static let everyKey = PenTextRun(
        start: 3,
        end: 7,
        fontFamily: "Inter",
        fontSize: 18,
        fontWeight: 700,
        isItalic: true,
        fill: PenHexColor("#E5484D"),
        underline: true,
        strikethrough: false,
        mention: "claude",
        inlinePadding: 4
    )

    /// The run's stored properties and whether each is set, by name.
    private func fields(of run: PenTextRun) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: Mirror(reflecting: run).children.compactMap { child in
            guard let label = child.label else { return nil }
            let mirror = Mirror(reflecting: child.value)
            let isSet = mirror.displayStyle != .optional || !mirror.children.isEmpty
            return (label, isSet)
        })
    }

    // MARK: Coverage

    @Test("every stored property of a run but its offsets is a style key, and every style key a property")
    func styleKeysCoverTheType() {
        let properties = Set(fields(of: Self.everyKey).keys).subtracting(["start", "end"])

        #expect(properties == Set(PenTextRun.StyleKey.allCases.map(\.rawValue)))
    }

    @Test("the fixture that sets every key does set every property")
    func fixtureSetsEveryKey() {
        #expect(!fields(of: Self.everyKey).values.contains(false))
    }

    @Test("every key the spans' wire form names survives a round trip through it")
    func wireKeysRoundTrip() throws {
        let stored = PenTextSpans(text: "0123456789", runs: [Self.everyKey]).metadataValue
        let read = try #require(try PenTextSpans(metadataValue: stored).runs.first)

        for key in PenTextRun.StyleKey.allCases {
            #expect(read.sets(key) == (key.wireKey != nil), "\(key)")
        }
        var expected = Self.everyKey
        for key in PenTextRun.StyleKey.allCases where key.wireKey == nil {
            expected.clear(key)
        }
        #expect(read == expected)
    }

    // MARK: Keys alone

    @Test("a run's keys alone have zero offsets, and a run with none sets no key")
    func keysOnly() {
        #expect(Self.everyKey.keysOnly == Self.everyKey.over(0 ..< 0))
        #expect(!Self.everyKey.setsNoKey)
        #expect(PenTextRun(start: 2, end: 9).setsNoKey)
        #expect(PenTextRun.noKeys == PenTextRun(start: 0, end: 0))
    }

    @Test("two runs have the same keys wherever they lie, and differ on any one key")
    func sameKeys() {
        #expect(Self.everyKey.hasSameKeys(as: Self.everyKey.over(20 ..< 30)))
        for key in PenTextRun.StyleKey.allCases {
            #expect(!Self.everyKey.hasSameKeys(as: Self.everyKey.clearing(key)), "\(key)")
        }
    }

    @Test("over a range keeps the keys and moves the offsets")
    func over() {
        let moved = Self.everyKey.over(10 ..< 12)

        #expect(moved.range == 10 ..< 12)
        #expect(moved.keysOnly == Self.everyKey.keysOnly)
    }

    // MARK: Overlay and clear

    @Test("a later run wins for every key it sets, each key on its own")
    func overlayEveryKey() {
        for key in PenTextRun.StyleKey.allCases {
            let later = PenTextRun.noKeys.taking(key, from: Self.everyKey)
            let overlaid = PenTextRun(start: 1, end: 2).overlaid(by: later)

            #expect(overlaid == later.over(1 ..< 2), "\(key)")
            #expect(overlaid.sets(key), "\(key)")
        }
    }

    @Test("a later run that sets nothing leaves every key")
    func overlayByNothing() {
        #expect(Self.everyKey.overlaid(by: .noKeys) == Self.everyKey)
        #expect(PenTextRun.noKeys.overlaid(by: Self.everyKey) == Self.everyKey.over(0 ..< 0))
    }

    @Test("clearing a key unsets it alone")
    func clearEveryKey() {
        for key in PenTextRun.StyleKey.allCases {
            let cleared = Self.everyKey.clearing(key)

            #expect(!cleared.sets(key), "\(key)")
            for other in PenTextRun.StyleKey.allCases where other != key {
                #expect(cleared.sets(other), "\(key) cleared \(other)")
            }
            #expect(cleared.range == Self.everyKey.range)
        }
    }
}
