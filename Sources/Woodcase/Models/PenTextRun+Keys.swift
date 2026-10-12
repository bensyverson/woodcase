//
//  PenTextRun+Keys.swift
//  Woodcase
//

import Foundation

/// A run's keys apart from its offsets: what an editor carries as "the style of a
/// character" — the keys runs set there — and compares, overlays and moves.
///
/// Where a value stands for keys alone, its `start` and `end` are both 0
/// (``keysOnly``). Every operation here walks ``StyleKey`` or compares whole values, so
/// none lists the keys by hand.
public extension PenTextRun {
    /// No key set: the keys of a character no run covers.
    static let noKeys = PenTextRun(start: 0, end: 0)

    /// The same keys over `range`.
    ///
    /// - Parameter range: The UTF-16 range to cover.
    /// - Returns: A copy covering `range`.
    func over(_ range: Range<Int>) -> PenTextRun {
        var run = self
        run.start = range.lowerBound
        run.end = range.upperBound
        return run
    }

    /// The keys alone, offsets zeroed.
    var keysOnly: PenTextRun {
        over(0 ..< 0)
    }

    /// Whether the run sets no key at all, so it changes nothing.
    var setsNoKey: Bool {
        keysOnly == Self.noKeys
    }

    /// Whether two runs set the same keys to the same values, wherever they lie.
    ///
    /// - Parameter other: The other run.
    /// - Returns: `true` when their keys are equal.
    func hasSameKeys(as other: PenTextRun) -> Bool {
        keysOnly == other.keysOnly
    }

    /// These keys with `later`'s over them: where both set a key, `later` wins, as a
    /// later run wins where runs overlap (``PenTextStyle/segments(of:runs:)``). The
    /// offsets are this run's.
    ///
    /// - Parameter later: The run laid over this one.
    /// - Returns: The overlaid run.
    func overlaid(by later: PenTextRun) -> PenTextRun {
        StyleKey.allCases.reduce(self) { run, key in
            later.sets(key) ? run.taking(key, from: later) : run
        }
    }
}
