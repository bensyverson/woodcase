//
//  PenLayoutEngine+Invalidation.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// Lays out again what a source invalidation names, keeping every other rect.
    ///
    /// The one call a host that runs its own pipeline needs: take
    /// ``EditableDocument/layoutInvalidation`` with the document's dirty tracking, expand
    /// and resolve the document, and hand both here with the previous rects and the
    /// measurement cache kept from the last call. The invalidation is translated against
    /// the expanded tree (``PenLayoutIndex/expandedIDs(for:)``) — so an edit to a component
    /// definition re-lays out the instances in other roots, and an override the whole
    /// instance it changes — the measurements of every translated id are forgotten, and
    /// the top-level nodes holding one are laid out again.
    ///
    /// The result equals ``layout(_:textMeasurer:)`` of the same document, bit for bit:
    /// `IncrementalLayoutEquivalenceTests` holds it to that over every fixture and a
    /// spread of writes.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The rects of the previous layout; when empty, everything is
    ///     laid out.
    ///   - invalidation: What the edits since that layout named, by source id.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - measurementCache: The host's measurement cache, kept across calls and only
    ///     ever filled by them.
    /// - Returns: Every expanded node's rect.
    static func layoutIncremental(
        _ document: PenDocument,
        previousRects: [String: PenRect],
        invalidation: PenLayoutInvalidation,
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        measurementCache: inout [String: MeasurementCacheEntry]
    ) -> [String: PenRect] {
        guard !invalidation.everything, !previousRects.isEmpty else {
            // A full pass fills no measurement cache, and nothing in the old one is known
            // to be good any more.
            measurementCache.removeAll()
            return layout(document, textMeasurer: textMeasurer)
        }
        let index = PenLayoutIndex(document)
        let dirty = index.expandedIDs(for: invalidation)
        for id in dirty {
            measurementCache.removeValue(forKey: id)
        }
        let dirtyRoots = Set(dirty.compactMap { index[$0]?.root })
        var memo = Memo(finals: measurementCache)
        let rects = layOutRoots(
            of: document, previousRects: previousRects,
            isDirty: { dirtyRoots.contains($0.id) },
            textMeasurer: textMeasurer, memo: &memo
        )
        measurementCache = memo.finals
        return rects
    }
}
