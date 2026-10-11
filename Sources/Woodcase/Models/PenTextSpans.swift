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

    /// Whether the runs were made for other content than `content`, so they apply to
    /// nothing.
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

    /// The runs that style `content`: all of them when they were made for it, none when
    /// they are stale.
    ///
    /// - Parameter content: The node's content as it is now.
    /// - Returns: ``runs``, or an empty list when ``isStale(for:)``.
    public func appliedRuns(to content: String) -> [PenTextRun] {
        isStale(for: content) ? [] : runs
    }
}
