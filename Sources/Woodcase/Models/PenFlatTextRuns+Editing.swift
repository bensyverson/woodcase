//
//  PenFlatTextRuns+Editing.swift
//  Woodcase
//

import Foundation

/// Flat runs following an edit of their text, and restyling a range of it. Each leaves
/// the runs flat (``PenFlatTextRuns``).
public extension PenFlatTextRuns {
    /// Follows an edit of the text: `range` is replaced by `insertedLength` code units
    /// set with `keys`. Runs before it stay, runs after it shift, a run it cuts keeps
    /// its parts outside it, and the inserted text takes `keys`.
    ///
    /// An insert is an empty `range`; a delete an `insertedLength` of 0.
    ///
    /// - Parameters:
    ///   - range: The UTF-16 range replaced, clamped to the text.
    ///   - insertedLength: The UTF-16 length of the text put in its place.
    ///   - keys: The keys the inserted text takes; its offsets are ignored.
    mutating func replace(_ range: Range<Int>, insertedLength: Int, keys: PenTextRun) {
        let lower = min(max(range.lowerBound, 0), length)
        let upper = min(max(range.upperBound, lower), length)
        let inserted = max(insertedLength, 0)
        let shift = inserted - (upper - lower)
        var edited: [PenTextRun] = []
        for run in runs {
            if run.start < lower {
                edited.append(run.over(run.start ..< min(run.end, lower)))
            }
            if run.end > upper {
                edited.append(run.over(max(run.start, upper) + shift ..< run.end + shift))
            }
        }
        if inserted > 0 {
            edited.append(keys.over(lower ..< lower + inserted))
        }
        length += shift
        setRuns(edited)
    }

    /// Changes the keys over `range`, gaps included, with `change`; a stretch left
    /// setting nothing is dropped.
    ///
    /// - Parameters:
    ///   - range: The UTF-16 range to restyle, clamped to the text.
    ///   - change: Changes one stretch's keys; its offsets are kept whatever it does.
    mutating func update(_ range: Range<Int>, _ change: (inout PenTextRun) -> Void) {
        let lower = min(max(range.lowerBound, 0), length)
        let range = lower ..< min(max(range.upperBound, lower), length)
        let outside = runs.flatMap { run -> [PenTextRun] in
            var parts: [PenTextRun] = []
            if run.start < range.lowerBound { parts.append(run.over(run.start ..< min(run.end, range.lowerBound))) }
            if run.end > range.upperBound { parts.append(run.over(max(run.start, range.upperBound) ..< run.end)) }
            return parts
        }
        let inside = stretches(in: range).map { stretch in
            var changed = stretch
            change(&changed)
            return changed.over(stretch.range)
        }
        setRuns(outside + inside)
    }

    /// Sets the keys `keys` sets over `range`, keeping every key it leaves unset.
    ///
    /// - Parameters:
    ///   - keys: The keys to set; its offsets are ignored.
    ///   - range: The UTF-16 range, clamped to the text.
    mutating func set(_ keys: PenTextRun, over range: Range<Int>) {
        update(range) { $0 = $0.overlaid(by: keys) }
    }

    /// Unsets `key` over `range`, so the node's own value shows there: un-bolding a
    /// range clears its weight rather than writing a regular one, and a run left setting
    /// nothing is dropped.
    ///
    /// - Parameters:
    ///   - key: The key to clear.
    ///   - range: The UTF-16 range, clamped to the text.
    mutating func clear(_ key: PenTextRun.StyleKey, over range: Range<Int>) {
        update(range) { $0.clear(key) }
    }
}
