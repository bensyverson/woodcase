//
//  PenFlatTextRuns.swift
//  Woodcase
//

import Foundation

/// The runs of a text kept flat — sorted, never overlapping, each setting at least one
/// key, and touching neighbors with the same keys merged — so every edit of the text
/// moves them with plain arithmetic.
///
/// A file's runs may overlap, a later one winning for the keys it sets
/// (``PenTextStyle/segments(of:runs:)``); flattening them once gives the same styling
/// as a list an editor can shift, split and restyle. Send every edit of the text through
/// ``replace(_:insertedLength:keys:)`` and the runs always fit it, so the spans written
/// from them (``spans(for:)``) are never stale. Offsets are UTF-16 code units, as
/// ``PenTextRun`` counts them.
///
/// ```swift
/// var runs = PenFlatTextRuns(spans: node.textSpans, content: text)
/// runs.replace(caret ..< caret, insertedLength: 1, keys: runs.keys(at: caret - 1))
/// runs.clear(.fontWeight, over: selection)   // un-bold: the node's weight shows again
/// let spans = runs.spans(for: draft)         // nil once no run is left
/// ```
///
/// Every key is handled through ``PenTextRun/StyleKey``, so none is listed here.
public struct PenFlatTextRuns: Friendly {
    /// The flat runs, as `metadata.woodcase.spans` stores them.
    public internal(set) var runs: [PenTextRun]

    /// The length of the text they cover, in UTF-16 code units.
    public internal(set) var length: Int

    /// Flattens `runs` over a text of `length` code units, each clamped to it.
    ///
    /// - Parameters:
    ///   - runs: The runs, in any order; where they overlap a later one wins for the
    ///     keys it sets.
    ///   - length: The UTF-16 length of the text.
    public init(_ runs: [PenTextRun] = [], length: Int) {
        let length = max(length, 0)
        self.length = length
        let clamped = runs.map { run in
            let lower = min(max(run.start, 0), length)
            return run.over(lower ..< min(max(run.end, lower), length))
        }.filter { !$0.range.isEmpty }
        let edges = Set([0, length] + clamped.flatMap { [$0.start, $0.end] }).sorted()
        self.runs = zip(edges, edges.dropFirst()).map { lower, upper in
            clamped.filter { $0.start <= lower && $0.end >= upper }
                .reduce(PenTextRun.noKeys) { $0.overlaid(by: $1) }
                .over(lower ..< upper)
        }
        normalize()
    }

    /// The runs that style `content`, flat: the spans' runs when they were made for it,
    /// and none when there are no spans or they are stale (``PenTextSpans/isStale(for:)``).
    ///
    /// Stale spans draw plain, so starting from none loses nothing visible; spans written
    /// from the result (``spans(for:)``) are fresh for `content` and replace them.
    ///
    /// - Parameters:
    ///   - spans: The node's spans, or `nil` for none.
    ///   - content: The node's content as it is now.
    public init(spans: PenTextSpans?, content: String) {
        self.init(spans?.appliedRuns(to: content) ?? [], length: content.utf16.count)
    }

    /// Whether no run sets anything.
    public var isEmpty: Bool {
        runs.isEmpty
    }

    /// The spans that store these runs for `text`, or `nil` when no run is left — the
    /// node then needs no spans at all.
    ///
    /// - Parameter text: The content the runs were made for; its UTF-16 length is
    ///   ``length``.
    /// - Returns: The spans, or `nil`.
    public func spans(for text: String) -> PenTextSpans? {
        isEmpty ? nil : PenTextSpans(text: text, runs: runs)
    }

    /// The keys the runs set on the character at `index`, offsets zeroed;
    /// ``PenTextRun/noKeys`` where no run covers it.
    ///
    /// - Parameter index: A UTF-16 offset into the text.
    /// - Returns: The keys at `index`.
    public func keys(at index: Int) -> PenTextRun {
        runs.first { $0.range.contains(index) }?.keysOnly ?? .noKeys
    }

    /// Every run's keys over the part of `range` it covers, and no keys over the gaps:
    /// the whole of `range`, stretch by stretch.
    ///
    /// - Parameter range: A UTF-16 range of the text.
    /// - Returns: The stretches, in order; empty for an empty range.
    public func stretches(in range: Range<Int>) -> [PenTextRun] {
        guard !range.isEmpty else { return [] }
        var stretches: [PenTextRun] = []
        var cursor = range.lowerBound
        for run in runs where run.end > range.lowerBound && run.start < range.upperBound {
            let lower = max(run.start, range.lowerBound)
            if lower > cursor { stretches.append(PenTextRun.noKeys.over(cursor ..< lower)) }
            let upper = min(run.end, range.upperBound)
            stretches.append(run.over(lower ..< upper))
            cursor = upper
        }
        if cursor < range.upperBound { stretches.append(PenTextRun.noKeys.over(cursor ..< range.upperBound)) }
        return stretches
    }

    /// Replaces the runs with `edited`, sorted and made flat again.
    ///
    /// - Parameter edited: Runs that do not overlap, in any order.
    mutating func setRuns(_ edited: [PenTextRun]) {
        runs = edited.sorted { $0.start < $1.start }
        normalize()
    }

    /// Drops runs that are empty or set nothing, and merges touching runs with the
    /// same keys.
    private mutating func normalize() {
        var merged: [PenTextRun] = []
        for run in runs where !run.range.isEmpty && !run.setsNoKey {
            if let last = merged.last, last.end == run.start, last.hasSameKeys(as: run) {
                merged[merged.count - 1].end = run.end
            } else {
                merged.append(run)
            }
        }
        runs = merged
    }
}
