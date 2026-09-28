//
//  ExpansionCache.swift
//  Woodcase
//

import Foundation

/// Caches expanded ref results to avoid redundant expansion work.
///
/// The cache is keyed by ref node ID. It is emptied — not pruned — whenever an
/// edit could change what an expansion produces; see
/// ``EditableDocument/invalidatingCaches(touching:_:)`` for the rule and why
/// it is whole-cache. What the cache buys is repeated expansion of an *unchanged*
/// document, which that still gives.
///
/// The cache is owned by the ``EditableDocument`` that made it and shares that
/// document's isolation: it is not `Sendable`, so the compiler keeps it — and the
/// document holding it — inside one isolation domain.
public final class ExpansionCache {
    /// Cached expansion results, keyed by ref node ID.
    var entries: [String: ExpandedRef] = [:]

    public init() {}

    /// Caches an expansion result.
    ///
    /// - Parameters:
    ///   - result: The expansion to remember.
    ///   - refNodeID: The ref node it was expanded from.
    func store(_ result: ExpandedRef, for refNodeID: String) {
        entries[refNodeID] = result
    }

    /// Removes all cached entries.
    func invalidateAll() {
        entries.removeAll()
    }
}
