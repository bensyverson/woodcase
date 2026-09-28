//
//  RootOverlap+Baseline.swift
//  Woodcase
//

import Foundation

package extension RootOverlap {
    /// The overlaps a document had before a write, and the text sizes measuring its roots
    /// found — what `introduced(since:in:)` measures the written document
    /// against.
    ///
    /// A write's overlap check measures the roots twice, and an edit changes a few texts
    /// at most, so the second measurement reads the first one's ``TextSizeCache`` and
    /// typesets only what changed. Last wave's profile of `set` found half of the check
    /// was Core Text setting the same texts twice.
    struct Baseline {
        /// Every pair of roots that overlapped.
        package let pairs: Set<Pair>

        /// The sizes the measurement typeset, for the one after the write to reuse.
        package let textSizes: TextSizeCache
    }

    /// Measures the roots before a write.
    ///
    /// - Parameters:
    ///   - document: The document, before the write.
    ///   - textSizes: The cache to measure texts through, which the baseline keeps.
    /// - Returns: The pairs, and the cache that measured them.
    static func baseline(in document: EditableDocument, textSizes: TextSizeCache = TextSizeCache()) -> Baseline {
        Baseline(
            pairs: Set(overlaps(among: roots(in: document, textMeasurer: textSizes.measurer)).map(\.pair)),
            textSizes: textSizes
        )
    }

    /// The overlaps a write introduced, measured through the baseline's text sizes.
    ///
    /// - Parameters:
    ///   - baseline: The measurement before the write.
    ///   - document: The document, after the write.
    /// - Returns: The overlaps the baseline did not have.
    static func introduced(since baseline: Baseline, in document: EditableDocument) -> [RootOverlap] {
        overlaps(among: roots(in: document, textMeasurer: baseline.textSizes.measurer)).filter { !baseline.pairs.contains($0.pair) }
    }
}
