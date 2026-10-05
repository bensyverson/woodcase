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
/// Invalidation is scoped to what an edit can move: a revision depends on the node
/// itself, on its descendants and on the nodes it renders, so an edit can only move the
/// revisions of the edited node, its ancestors, every instance rendering one of those,
/// their ancestors, and so on — the closure
/// ``EditableDocument/revisionDependents(of:)`` walks, which for an edit clear of every
/// component is its spine. That closure is what
/// ``EditableDocument/invalidatingCaches(touching:_:)`` forgets, and every other entry
/// stays warm — which is what makes a read after a write cheap as well as a cold read.
/// A forgotten node keeps its ``encodings`` entry unless the edit wrote it, so refolding
/// the closure costs a few string combines per node, not a JSON encoding: an edit inside
/// a component nested in 25 others, with 400 instances on the page, refolds 512 nodes in
/// about 0.56 ms (release, `ComponentLoopEditCostProbe`'s document, load about 10).
///
/// Components that render each other share a group revision
/// (``EditableDocument/revision(of:)``), kept per member in ``cycles``. A revision that
/// reads one is as cachable as any other; only a member's working hash, folded while its
/// group is being resolved, is never stored. An edit whose spine crosses a member
/// takes the whole cache, because the group revision it moves is read by nodes on no
/// spine — the case a component edit already covers, and a ref to a node that is not a
/// component would otherwise miss.
///
/// The cache is owned by the ``EditableDocument`` that made it and shares that
/// document's isolation; it is not `Sendable`, exactly as ``ExpansionCache`` is not.
final class RevisionCache {
    /// Cached revisions, keyed by node ID.
    var entries: [String: String] = [:]

    /// What a reference to each member of a cyclic component group folds in, keyed by
    /// the member's id: the group's shared revision with the member's id.
    var cycles: [String: String] = [:]

    /// A node's own canonical encoding, hashed: where its fold starts before any child
    /// or component is folded in.
    struct Encoding: Friendly {
        /// The hasher, having consumed the node's encoding.
        var hasher: FNV1aHasher

        /// Whether the node declared an empty children list when it was encoded, which
        /// the encoding spells as `"children": []`.
        var declaresEmptyChildren: Bool

        /// The ids the node renders (``PenNode/renderedComponentIDs``), which like the
        /// encoding depend on its content alone.
        var rendered: [String]
    }

    /// Each node's own encoding, keyed by node ID.
    ///
    /// Encoding a node as canonical JSON is nearly all of what folding it costs; folding
    /// in its children's and components' revisions is a few dozen bytes each. The
    /// encoding depends on the node's own content alone, so an edit that only moves a
    /// node's revision — a descendant edited, a component it renders redrawn — keeps it,
    /// and refolding the spines and instances such an edit forgets costs a few string
    /// combines per node rather than a JSON encoding. It is forgotten only for the nodes
    /// an edit writes (``forgetEncodings(of:)``).
    var encodings: [String: Encoding] = [:]

    /// Whether nothing is cached.
    var isEmpty: Bool {
        entries.isEmpty && cycles.isEmpty
    }

    init() {}

    /// Caches a node's revision.
    ///
    /// - Parameters:
    ///   - revision: The revision to remember.
    ///   - nodeID: The node it was computed for.
    func store(_ revision: String, for nodeID: String) {
        entries[nodeID] = revision
        writes &+= 1
    }

    /// Caches the revision a reference to a member of a cyclic group folds in.
    ///
    /// - Parameters:
    ///   - revision: The group's revision with the member's id.
    ///   - member: The member.
    func storeCycle(_ revision: String, for member: String) {
        cycles[member] = revision
        writes &+= 1
    }

    /// How many revisions have been stored, so an edit can tell whether anything was
    /// cached while it ran.
    private(set) var writes = 0

    /// Forgets one node's revision, leaving every other entry alone — unless the node
    /// is a member of a cyclic component group, whose shared revision other nodes have
    /// folded in, in which case it forgets everything.
    ///
    /// - Parameter nodeID: The node to forget.
    func forget(_ nodeID: String) {
        guard cycles[nodeID] == nil else { return invalidateAll() }
        entries.removeValue(forKey: nodeID)
    }

    /// Forgets the encodings of nodes whose content may have changed.
    ///
    /// - Parameter nodeIDs: The nodes an edit wrote.
    func forgetEncodings(of nodeIDs: [String]) {
        guard !encodings.isEmpty else { return }
        for nodeID in nodeIDs {
            encodings.removeValue(forKey: nodeID)
        }
    }

    /// Removes all cached entries.
    func invalidateAll() {
        entries.removeAll()
        cycles.removeAll()
        encodings.removeAll()
    }
}
