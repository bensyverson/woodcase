//
//  PenTextSpans.swift
//  Woodcase
//

import Foundation

/// A text node's rich text: its styled runs, and the text they were made for.
///
/// `content` stays the plain string Pen shows — Pen has no rich text, and deletes a run
/// array written into `content` — so the styling is kept beside it, in the node's
/// `woodcase.spans` metadata key. ``text`` is the content the runs were made for. When the
/// content no longer equals it (someone edited the words in Pen, which keeps metadata but
/// does not understand it), the runs are stale: they apply to nothing and the text draws
/// plain, rather than styling the wrong characters.
///
/// Offsets in ``runs`` are UTF-16 code units into ``text`` (see ``PenTextRun``).
public struct PenTextSpans: Friendly {
    /// The content the runs were made for.
    public var text: String

    /// The runs, in order; a later run wins where runs overlap.
    public var runs: [PenTextRun]

    /// Creates spans for a text.
    ///
    /// - Parameters:
    ///   - text: The content the runs were made for.
    ///   - runs: The runs, offsets in UTF-16 code units into `text`.
    public init(text: String, runs: [PenTextRun]) {
        self.text = text
        self.runs = runs
    }

    /// Whether the runs were made for other content than `content`.
    ///
    /// Stale runs over part of the text apply to nothing; a run over the whole of it is
    /// stretched over the new content (``appliedRuns(to:)``).
    ///
    /// The comparison is of UTF-16 code units, not Swift's `==`: two strings equal only by
    /// Unicode equivalence ("é" precomposed and decomposed) have different offsets, so runs
    /// made for one would style the wrong characters of the other.
    ///
    /// - Parameter content: The node's content as it is now.
    /// - Returns: `true` when `content` differs from ``text`` in any code unit.
    public func isStale(for content: String) -> Bool {
        !content.utf16.elementsEqual(text.utf16)
    }

    /// The runs that style `content`: all of them when they were made for it; when they
    /// are stale, each run that covered the whole of ``text``, stretched over the whole of
    /// `content`.
    ///
    /// Ben's ruling of 2026-10-15 (leaf 0LwfSn): another editor — Pen, which keeps metadata
    /// but cannot see spans — may change the words, and a style the author gave the whole
    /// text still belongs to the whole text. Where a run over part of the text belongs in
    /// new words cannot be known, so it is dropped. A whole-text mention is dropped too: it
    /// names the words it was made for. Nothing is stretched over empty content.
    ///
    /// - Parameter content: The node's content as it is now.
    /// - Returns: ``runs``, or the whole-text runs stretched when ``isStale(for:)``.
    public func appliedRuns(to content: String) -> [PenTextRun] {
        guard isStale(for: content) else { return runs }
        let length = content.utf16.count
        guard length > 0 else { return [] }
        return runs.filter(coversWholeText).map { run in
            var stretched = run
            stretched.start = 0
            stretched.end = length
            return stretched
        }
    }

    /// The runs that do not style `content`: none when they were made for it; when they
    /// are stale, every run but those ``appliedRuns(to:)`` stretches.
    ///
    /// - Parameter content: The node's content as it is now.
    /// - Returns: The runs ignored, as stored.
    public func ignoredRuns(for content: String) -> [PenTextRun] {
        guard isStale(for: content) else { return [] }
        guard !content.utf16.isEmpty else { return runs }
        return runs.filter { !coversWholeText($0) }
    }

    /// Whether a run covers all of ``text`` and may follow it into new words: a non-empty
    /// text, from its first code unit to past its last, and not a mention.
    private func coversWholeText(_ run: PenTextRun) -> Bool {
        let length = text.utf16.count
        return length > 0 && run.start <= 0 && run.end >= length && run.mention == nil
    }
}
