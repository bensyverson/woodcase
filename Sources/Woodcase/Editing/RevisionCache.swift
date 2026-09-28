//
//  RevisionCache.swift
//  Woodcase
//

import Foundation

/// Remembers the content revision of each node, so reading a whole tree costs one
/// pass over the document rather than one walk per row.
///
/// ``EditableDocument/revision(of:)`` is a Merkle hash: a node's revision mixes in
/// every child's revision, so computing it for every node of a tree of *n* nodes and
/// depth *d* costs O(n·d) unmemoized — a `woodcase tree --json` of a deep file hashes
/// the same leaf once per ancestor. With this cache each node is hashed once.
///
/// Measured on 2026-08-31 with
/// `swift test --quiet --filter TreeTests`, reading the `BUDGET` lines: the settled
/// read of the 5000-node synthetic fixture takes **773.8 ms** memoized and
/// **1044.4 ms** with the memoization removed (debug build, five repetitions, minimum
/// reported, the two runs back to back on a lightly loaded machine). The unmemoized
/// figure is over that budget's own 1000 ms debug limit, so the cache is what lets
/// every row carry a revision at no cost. Absolute numbers here move by a factor of
/// two with sibling builds running; only the paired comparison means anything.
///
/// Invalidation is spine-scoped for an edit that touches no component: a revision
/// depends on the node itself, on its descendants and on the components it renders, so
/// an edit clear of all that can only move the revisions of the edited node and its
/// ancestors. That spine is what ``EditableDocument/invalidatingCaches(touching:_:)``
/// forgets, and every other entry stays warm — which is what makes a read after a write
/// cheap as well as a cold read. An edit that *does* touch a component takes the whole
/// cache, the way ``ExpansionCache`` always does, because the instances it moves are a
/// closure over the ref graph rather than a walk up one spine.
///
/// Not every revision is cachable. One computed by cutting a cycle in the component
/// graph depends on which node the walk started from, so
/// ``EditableDocument/revision(of:)`` declines to store it — every entry here is one
/// that no cut took part in.
///
/// The cache is owned by the ``EditableDocument`` that made it and shares that
/// document's isolation; it is not `Sendable`, exactly as ``ExpansionCache`` is not.
final class RevisionCache {
    /// Cached revisions, keyed by node ID.
    var entries: [String: String] = [:]

    init() {}

    /// Caches a node's revision.
    ///
    /// - Parameters:
    ///   - revision: The revision to remember.
    ///   - nodeID: The node it was computed for.
    func store(_ revision: String, for nodeID: String) {
        entries[nodeID] = revision
    }

    /// Forgets one node's revision, leaving every other entry alone.
    ///
    /// - Parameter nodeID: The node to forget.
    func forget(_ nodeID: String) {
        entries.removeValue(forKey: nodeID)
    }

    /// Removes all cached entries.
    func invalidateAll() {
        entries.removeAll()
    }
}
