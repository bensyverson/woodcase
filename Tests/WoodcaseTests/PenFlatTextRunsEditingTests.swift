//
//  PenFlatTextRunsEditingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Flat runs follow every edit of their text — insert, delete, replace — and take a
/// key set or cleared over a range, staying flat: sorted, never overlapping, each
/// setting a key, touching neighbors with the same keys merged.
struct PenFlatTextRunsEditingTests {
    private typealias Run = PenTextRun

    /// Whether runs are flat: sorted, apart, each non-empty and setting a key, and no two
    /// touching neighbors setting the same keys.
    private func isFlat(_ runs: PenFlatTextRuns) -> Bool {
        let list = runs.runs
        let each = list.allSatisfy { !$0.range.isEmpty && !$0.setsNoKey && $0.start >= 0 && $0.end <= runs.length }
        let pairs = zip(list, list.dropFirst()).allSatisfy { left, right in
            left.end <= right.start && !(left.end == right.start && left.hasSameKeys(as: right))
        }
        return each && pairs
    }

    // MARK: Shifting with an edit

    @Test("inserting inside a gap shifts the runs after it and gives the inserted text its keys")
    func insertShifts() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 2, isItalic: true), Run(start: 6, end: 11, fontWeight: 700)], length: 11)

        runs.replace(4 ..< 4, insertedLength: 3, keys: .noKeys)

        #expect(runs.runs == [Run(start: 0, end: 2, isItalic: true), Run(start: 9, end: 14, fontWeight: 700)])
        #expect(runs.length == 14)
    }

    @Test("inserting inside a run with other keys splits it around the inserted text")
    func insertSplitsRun() {
        var runs = PenFlatTextRuns([Run(start: 2, end: 8, fontWeight: 700)], length: 10)

        runs.replace(4 ..< 4, insertedLength: 2, keys: Run(start: 0, end: 0, isItalic: true))

        #expect(runs.runs == [
            Run(start: 2, end: 4, fontWeight: 700),
            Run(start: 4, end: 6, isItalic: true),
            Run(start: 6, end: 10, fontWeight: 700),
        ])
        #expect(isFlat(runs))
    }

    @Test("inserted text with a run's keys extends the run")
    func insertExtends() {
        var runs = PenFlatTextRuns([Run(start: 6, end: 11, fontWeight: 700)], length: 11)

        runs.replace(11 ..< 11, insertedLength: 1, keys: Run(start: 0, end: 0, fontWeight: 700))

        #expect(runs.runs == [Run(start: 6, end: 12, fontWeight: 700)])
    }

    @Test("inserting at the very start shifts every run")
    func insertAtStart() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 3, underline: true)], length: 3)

        runs.replace(0 ..< 0, insertedLength: 2, keys: .noKeys)

        #expect(runs.runs == [Run(start: 2, end: 5, underline: true)])
        #expect(runs.length == 5)
    }

    @Test("deleting a stretch a run crosses keeps the run's parts outside it")
    func deleteCuts() {
        var runs = PenFlatTextRuns([Run(start: 2, end: 8, fontWeight: 700)], length: 10)

        runs.replace(4 ..< 6, insertedLength: 0, keys: .noKeys)

        #expect(runs.runs == [Run(start: 2, end: 6, fontWeight: 700)])
        #expect(runs.length == 8)
    }

    @Test("deleting a whole run removes it")
    func deleteRemoves() {
        var runs = PenFlatTextRuns([Run(start: 2, end: 4, fontWeight: 700)], length: 6)

        runs.replace(1 ..< 5, insertedLength: 0, keys: .noKeys)

        #expect(runs.isEmpty)
        #expect(runs.length == 2)
    }

    @Test("deleting what lay between two runs with the same keys merges them")
    func deleteMerges() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 2, isItalic: true), Run(start: 4, end: 6, isItalic: true)], length: 6)

        runs.replace(2 ..< 4, insertedLength: 0, keys: .noKeys)

        #expect(runs.runs == [Run(start: 0, end: 4, isItalic: true)])
    }

    @Test("replacing across two runs keeps their outer parts and gives the new text its keys")
    func replaceAcross() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 4, isItalic: true), Run(start: 4, end: 8, fontWeight: 700)], length: 10)

        runs.replace(2 ..< 6, insertedLength: 1, keys: Run(start: 0, end: 0, underline: true))

        #expect(runs.runs == [
            Run(start: 0, end: 2, isItalic: true),
            Run(start: 2, end: 3, underline: true),
            Run(start: 3, end: 5, fontWeight: 700),
        ])
        #expect(runs.length == 7)
    }

    @Test("an edit range outside the text is clamped to it")
    func replaceClamps() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 2, isItalic: true)], length: 4)

        runs.replace(3 ..< 99, insertedLength: 0, keys: .noKeys)

        #expect(runs.runs == [Run(start: 0, end: 2, isItalic: true)])
        #expect(runs.length == 3)
    }

    // MARK: Setting and clearing a key over a range

    @Test("updating a range splits runs at its edges and fills the gaps")
    func updateSplits() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 4, isItalic: true)], length: 10)

        runs.update(2 ..< 6) { $0.fontWeight = 700 }

        #expect(runs.runs == [
            Run(start: 0, end: 2, isItalic: true),
            Run(start: 2, end: 4, fontWeight: 700, isItalic: true),
            Run(start: 4, end: 6, fontWeight: 700),
        ])
    }

    @Test("setting keys over a range overlays them, keeping the keys they do not set")
    func setOverlays() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 6, fontWeight: 300, isItalic: true)], length: 8)

        runs.set(Run(start: 0, end: 0, fontWeight: 700, mention: "ana"), over: 4 ..< 8)

        #expect(runs.runs == [
            Run(start: 0, end: 4, fontWeight: 300, isItalic: true),
            Run(start: 4, end: 6, fontWeight: 700, isItalic: true, mention: "ana"),
            Run(start: 6, end: 8, fontWeight: 700, mention: "ana"),
        ])
    }

    @Test("clearing a key over a range unsets it there so the node's own value shows, and keeps it elsewhere")
    func clearOverRange() {
        var runs = PenFlatTextRuns([Run(start: 0, end: 8, fontWeight: 700, underline: true)], length: 8)

        runs.clear(.fontWeight, over: 2 ..< 5)

        #expect(runs.runs == [
            Run(start: 0, end: 2, fontWeight: 700, underline: true),
            Run(start: 2, end: 5, underline: true),
            Run(start: 5, end: 8, fontWeight: 700, underline: true),
        ])
    }

    @Test("clearing a key everywhere drops the runs left setting nothing")
    func clearEverywhere() {
        var runs = PenFlatTextRuns([
            Run(start: 0, end: 4, fontWeight: 700),
            Run(start: 4, end: 8, fontWeight: 300, isItalic: true),
        ], length: 8)

        runs.clear(.fontWeight, over: 0 ..< runs.length)

        #expect(runs.runs == [Run(start: 4, end: 8, isItalic: true)])
    }

    @Test("clearing each key works for every key the type holds")
    func clearEachKey() {
        for key in PenTextRun.StyleKey.allCases {
            var runs = PenFlatTextRuns([PenTextRunKeysTests.everyKey.over(0 ..< 4)], length: 4)

            runs.clear(key, over: 0 ..< 4)

            #expect(runs.runs == [PenTextRunKeysTests.everyKey.clearing(key).over(0 ..< 4)], "\(key)")
        }
    }

    @Test("every edit leaves the runs flat")
    func editsStayFlat() {
        var runs = PenFlatTextRuns([
            Run(start: 0, end: 5, fontWeight: 700),
            Run(start: 3, end: 9, isItalic: true),
            Run(start: 9, end: 12, isItalic: true),
        ], length: 12)
        #expect(isFlat(runs))

        runs.replace(4 ..< 7, insertedLength: 5, keys: Run(start: 0, end: 0, isItalic: true))
        #expect(isFlat(runs))
        runs.clear(.isItalic, over: 0 ..< 6)
        #expect(isFlat(runs))
        runs.set(Run(start: 0, end: 0, fontWeight: 700), over: 0 ..< runs.length)
        #expect(isFlat(runs))
        runs.clear(.fontWeight, over: 0 ..< runs.length)
        #expect(isFlat(runs))
        #expect(runs.runs.allSatisfy { !$0.sets(.fontWeight) })
    }
}
