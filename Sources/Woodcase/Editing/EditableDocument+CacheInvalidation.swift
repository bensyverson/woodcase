//
//  EditableDocument+CacheInvalidation.swift
//  Woodcase
//

import Foundation

/// The one rule that keeps the ``ExpansionCache`` and the ``RevisionCache`` honest.
///
/// A cached expansion is a snapshot of a component's whole subtree, so *any* edit
/// inside that subtree can falsify it — not just an edit to the ref or to the
/// component's root. A cached revision is a hash of a node, its descendants *and the
/// components it renders*, so an edit falsifies it for the edited node and every
/// ancestor above it, and — once a component is involved — for every instance that
/// draws what was edited, wherever it sits. Rather than ask each operation to remember
/// either rule, every mutating path wraps itself in
/// ``EditableDocument/invalidatingCaches(touching:_:)`` and names the nodes it
/// touches; the rules decide.
///
/// Both rules read the touched nodes *before and after* the mutation. Both readings
/// are needed: a delete or a move out of a component only looks like component work
/// beforehand, and an insert or a move in only afterwards — and for revisions, a move
/// has one spine before it and a different one after.
extension EditableDocument {
    /// Runs a mutation, dropping the cached expansions and revisions it could have
    /// falsified.
    ///
    /// Expansion invalidation is whole-cache on purpose. A per-component index would
    /// have to be right about which component a node belongs to at two points in time,
    /// for an edit that may be moving the node between components — the failure mode
    /// this fixes. The cache exists to spare repeated expansion of an *unchanged*
    /// document, which whole-cache invalidation still does.
    ///
    /// Revision invalidation is spine-scoped *unless a component is involved*. A
    /// revision depends on the node, its descendants, and — for a `ref` — the
    /// components it renders, so an edit that touches none of that machinery can only
    /// move the revisions of the edited node and its ancestors. Dropping the whole
    /// cache for those would make every read after every write a full rehash.
    ///
    /// An edit that *does* touch a component is the other case, and it takes the whole
    /// revision cache with it. The nodes whose revisions such an edit can move are the
    /// instances of the component, their ancestors, the instances of any component
    /// holding one of those instances, and so on — a closure over both the tree and the
    /// ref graph, with a repoint able to add an edge the ref itself does not name.
    /// Keeping an index of that right through moves between components is the failure
    /// mode the expansion rule already declines to risk, and the condition is the same
    /// one: ``expansionCanDepend(on:)`` is true exactly when a node is a `ref`, is a
    /// component, or is inside one — which is exactly when a fold-in edge can be in
    /// play. So the two caches drop together, on one predicate, read before and after.
    ///
    /// - Parameters:
    ///   - subjects: The nodes the mutation touches — its subject, and for a move
    ///     or an insert the parent it lands under. Ids that name nothing are ignored.
    ///   - body: The mutation.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `body` throws. The caches are still checked, because a
    ///   throwing operation may have written before it threw.
    func invalidatingCaches<T>(touching subjects: [String], _ body: () throws -> T) rethrows -> T {
        let affectedBefore = subjects.contains { expansionCanDepend(on: $0) }
        forgetRevisions(along: subjects)
        defer {
            forgetRevisions(along: subjects)
            if affectedBefore || subjects.contains(where: { expansionCanDepend(on: $0) }) {
                _expansionCache?.invalidateAll()
                _revisionCache?.invalidateAll()
            }
        }
        return try body()
    }

    /// Forgets the cached revision of every subject and of every ancestor above it.
    ///
    /// The walk stops at a node it has already visited in this pass, so an insert of a
    /// thousand-node subtree pays for the shared spine once rather than a thousand
    /// times; the same check makes a transiently cyclic parent map terminate.
    ///
    /// A subject's *descendants* are deliberately left alone: their revisions cannot
    /// have moved unless they were touched themselves, in which case they are subjects
    /// too — and an id that comes back into the document later arrives as the subject
    /// of the insert that brings it. Instances that render a touched component are not
    /// on this walk either; they are covered by the whole-cache drop in
    /// ``invalidatingCaches(touching:_:)``, which is the case this spine walk cannot see.
    ///
    /// - Parameter subjects: The nodes the mutation touches.
    func forgetRevisions(along subjects: [String]) {
        guard let cache = _revisionCache, !cache.entries.isEmpty else { return }
        var visited: Set<String> = []
        for subject in subjects {
            var current = subject
            while visited.insert(current).inserted {
                cache.forget(current)
                guard let parent = parents[current] else { break }
                current = parent
            }
        }
    }

    /// Whether a cached expansion could depend on the node as it stands right now.
    ///
    /// True for a `ref` node (its own expansion is cached under its id), for a
    /// reusable component (every instance of it expands from its subtree), and for
    /// any node inside a reusable component's subtree (it *is* part of that
    /// expansion). False for a node that names nothing — an id that has not been
    /// inserted yet, or has just been deleted, cannot be inside a component; the
    /// other reading of the pair covers that half of the edit.
    ///
    /// - Parameter nodeID: The node to test.
    /// - Returns: `true` if an expansion could be reading this node.
    func expansionCanDepend(on nodeID: String) -> Bool {
        guard let node = nodes[nodeID] else { return false }
        if case .ref = node.kind { return true }
        if node.common.reusable == true { return true }
        return ancestors(of: nodeID).contains { nodes[$0]?.common.reusable == true }
    }

    /// The nodes an editing operation touches.
    ///
    /// Document-level operations — variables, imports, theme axes — touch no node.
    /// Expansion is a structural read: it clones component subtrees and leaves
    /// variable references in place for the resolver, so a variable's *value*
    /// cannot falsify a cached expansion. Nor can it falsify a revision: a revision
    /// hashes what the file stores, and a variable's value is stored on the document,
    /// not on the node — which is why ``documentRevision`` is computed rather than
    /// cached.
    ///
    /// - Parameter operation: The operation about to be applied.
    /// - Returns: The ids to weigh the rules against, possibly empty.
    func subjects(of operation: EditOperation) -> [String] {
        switch operation {
        case let .insertNode(op):
            // The whole inserted subtree: it may carry a reusable component that a
            // ref was already caching an unexpanded result for.
            collectInsertedIDs(in: op.node) + [op.parentID].compactMap(\.self)
        case let .deleteNode(op):
            // ``deleteNode(_:)`` widens this to the whole subtree it removes.
            [op.nodeID]
        case let .moveNode(op):
            [op.nodeID] + [op.newParentID].compactMap(\.self)
        case let .replaceSubtree(op):
            // Both sides: the subtree going away may hold a component a ref cached,
            // and the one arriving may hold its replacement.
            descendantIDs(of: op.node.id) + collectInsertedIDs(in: op.node)
        case let .updateCommon(op):
            [op.nodeID]
        case let .updateKind(op):
            [op.nodeID]
        case let .setProperties(op):
            [op.nodeID]
        case let .overrideDescendant(op):
            [op.refNodeID]
        case let .overrideRoot(op):
            [op.refNodeID]
        case let .detachRef(op):
            [op.refNodeID]
        case .addVariable, .removeVariable, .updateVariable,
             .addImport, .removeImport, .updateImport,
             .addThemeAxis, .removeThemeAxis, .updateThemeAxis:
            []
        }
    }

    /// The nodes a CRDT mutation touches.
    ///
    /// Remote operations reach the flat store only as ``DocumentMutation``s, and
    /// ``CRDTDocument`` emits one for *every* parent relationship a move changed,
    /// so weighing each mutation covers the reparenting that
    /// ``reconcileChildrenWithParents()`` then re-derives from it.
    ///
    /// - Parameter mutation: The mutation about to be applied.
    /// - Returns: The ids to weigh the rules against, possibly empty.
    func subjects(of mutation: DocumentMutation) -> [String] {
        switch mutation {
        case let .setNode(node):
            [node.id]
        case let .removeNode(nodeID):
            [nodeID]
        case let .setChildren(parentID, _):
            // Order matters inside a component; at the root it cannot. A root
            // reordering moves no node's revision either — only the document's,
            // which is not cached.
            [parentID].compactMap(\.self)
        case let .setParent(nodeID, parentID):
            [nodeID] + [parentID].compactMap(\.self)
        case let .removeParent(nodeID):
            [nodeID]
        case .setVariable, .removeVariable,
             .setImport, .removeImport,
             .setThemeAxis, .removeThemeAxis:
            []
        }
    }
}
