//
//  ExpansionCache.swift
//  Woodcase
//

import Foundation

/// Caches expanded ref results to avoid redundant expansion work.
///
/// The cache is keyed by ref node ID. An edit drops the entry of every instance
/// whose expansion it can change — the instances in the edit's revision closure,
/// since an expansion reads exactly what its instance renders — and keeps the rest;
/// see ``EditableDocument/invalidatingCaches(touching:_:)``. The component loops
/// memoized beside the entries are dropped only by an edit that can change the
/// component graph.
///
/// The cache is owned by the ``EditableDocument`` that made it and shares that
/// document's isolation: it is not `Sendable`, so the compiler keeps it — and the
/// document holding it — inside one isolation domain.
public final class ExpansionCache {
    /// Cached expansion results, keyed by ref node ID.
    var entries: [String: ExpandedRef] = [:]

    /// The document's component loops, found on first use, and dropped by an edit that
    /// can change the component graph
    /// (``EditableDocument/invalidatesComponentLoops(_:before:after:)``).
    var componentLoops: ComponentLoopIndex?

    public init() {}

    /// Caches an expansion result.
    ///
    /// - Parameters:
    ///   - result: The expansion to remember.
    ///   - refNodeID: The ref node it was expanded from.
    func store(_ result: ExpandedRef, for refNodeID: String) {
        entries[refNodeID] = result
        writes &+= 1
    }

    /// How many expansions have been stored, so an edit can tell whether anything was
    /// cached while it ran.
    private(set) var writes = 0

    /// Removes all cached entries.
    func invalidateAll() {
        entries.removeAll()
        componentLoops = nil
    }
}
