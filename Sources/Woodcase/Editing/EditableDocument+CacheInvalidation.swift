//
//  EditableDocument+CacheInvalidation.swift
//  Woodcase
//

import Foundation

/// The one rule that keeps the ``ExpansionCache`` and the ``RevisionCache`` honest.
///
/// A cached revision is a hash of a node, its descendants *and the nodes it renders*,
/// and a cached expansion is a clone of everything an instance renders. So an edit
/// falsifies the revision of the edited node and of every ancestor above it — and, for
/// each node on that spine that something renders, of every instance rendering it, every
/// ancestor of those, every instance of a component holding one of them, and so on: a
/// closure over the tree and the render graph together, which
/// ``revisionDependents(of:)`` walks with the ``ComponentReferrers`` index. A cached
/// expansion can only read what its instance renders, so the instances in that same
/// closure are the expansions it can falsify.
///
/// Rather than ask each operation to remember the rule, every mutating path wraps itself
/// in ``EditableDocument/invalidatingCaches(touching:_:)`` and names the nodes it
/// touches — every node whose content it writes, and for a move or an insert the parent
/// it lands under. The closure is read *before and after* the mutation. Both readings are
/// needed: a delete or a move out of a component is only reached from that component
/// beforehand, and an insert or a move in only afterwards; a repointed instance renders
/// one component before and another after.
extension EditableDocument {
    /// Runs a mutation, dropping the cached revisions and expansions it could have
    /// falsified and no others.
    ///
    /// The revisions forgotten are the closure ``revisionDependents(of:)`` reads, before
    /// and after; a subject's own encoding is forgotten too, since its content may have
    /// changed. The expansions dropped are the instances in the same closure. The
    /// component graph's loops (``ComponentLoopIndex``), memoized with the expansions,
    /// are dropped only when the edit can change the graph:
    /// ``invalidatesComponentLoops(_:before:after:)``.
    ///
    /// The walk costs the size of the closure: an edit clear of every component is its
    /// spine, and an edit inside a component reaches each instance of it once, however
    /// many components nest it.
    ///
    /// - Parameters:
    ///   - subjects: The nodes the mutation touches — every node whose content it writes,
    ///     and for a move or an insert the parent it lands under. Ids that name nothing
    ///     are ignored.
    ///   - body: The mutation.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `body` throws. The caches are still checked, because a
    ///   throwing operation may have written before it threw.
    func invalidatingCaches<T>(touching subjects: [String], _ body: () throws -> T) rethrows -> T {
        forgetDependents(of: subjects)
        let sitesBefore = componentGraphSites(of: subjects)
        let placesBefore = subjects.map(place(of:))
        let writesBefore = cacheWrites
        defer {
            let renderingChanged = reindexReferrers(of: subjects)
            // The closure after differs from the one already forgotten only if a subject
            // moved, arrived, left or renders something else — or if the mutation cached
            // something while it ran, which may have read it half done.
            if renderingChanged || cacheWrites != writesBefore || subjects.map(place(of:)) != placesBefore {
                forgetDependents(of: subjects)
            }
            _revisionCache?.forgetEncodings(of: subjects)
            // Loops first memoized during the mutation may have read it half done.
            if let sitesAfter = componentGraphSites(of: subjects),
               sitesBefore.map({ invalidatesComponentLoops(subjects, before: $0, after: sitesAfter) }) ?? true
            {
                _expansionCache?.componentLoops = nil
            }
        }
        return try body()
    }

    /// Forgets the cached revision and expansion of every node whose revision can depend
    /// on a subject as the document stands now.
    ///
    /// - Parameter subjects: The nodes the mutation touches.
    func forgetDependents(of subjects: [String]) {
        let revisions = _revisionCache.flatMap { $0.isEmpty ? nil : $0 }
        let expansions = _expansionCache.flatMap { $0.entries.isEmpty ? nil : $0 }
        guard revisions != nil || expansions != nil else { return }
        for nodeID in revisionDependents(of: subjects) {
            revisions?.forget(nodeID)
            expansions?.entries[nodeID] = nil
        }
    }

    /// Every node whose revision can depend on a subject: each subject, each ancestor of
    /// one, each node that renders one of those, each of *its* ancestors, and so on.
    ///
    /// The walk visits each node once, so a spine shared by many subjects — an inserted
    /// subtree, the instances of one component — is paid for once, and a transiently
    /// cyclic parent map or render graph terminates.
    ///
    /// - Parameter subjects: The nodes to start from.
    /// - Returns: The closure, subjects included.
    func revisionDependents(of subjects: [String]) -> Set<String> {
        let referrers = componentReferrers
        var visited: Set<String> = []
        var pending = subjects
        while let start = pending.popLast() {
            var current = start
            while visited.insert(current).inserted {
                pending.append(contentsOf: referrers.referrers(of: current))
                guard let parent = parents[current] else { break }
                current = parent
            }
        }
        return visited
    }

    /// The document's ``ComponentReferrers``, built from every node on first use and kept
    /// in step by ``invalidatingCaches(touching:_:)`` after that.
    var componentReferrers: ComponentReferrers {
        if let built = _componentReferrers { return built }
        let built = ComponentReferrers(nodes: nodes)
        _componentReferrers = built
        return built
    }

    /// Re-reads what each subject renders into the referrer index, if it has been built.
    ///
    /// - Parameter subjects: The nodes a mutation touched.
    /// - Returns: Whether any subject's entry changed.
    @discardableResult
    func reindexReferrers(of subjects: [String]) -> Bool {
        guard _componentReferrers != nil else { return false }
        var changed = false
        for nodeID in subjects {
            if _componentReferrers?.reindex(nodeID, rendering: nodes[nodeID]?.renderedComponentIDs ?? []) == true {
                changed = true
            }
        }
        return changed
    }

    /// Where a node is: whether it exists, and its parent.
    private func place(of nodeID: String) -> Place {
        Place(exists: nodes[nodeID] != nil, parent: parents[nodeID])
    }

    /// A node's existence and parent, compared before and after a mutation.
    private struct Place: Friendly {
        /// Whether the node is in the document.
        var exists: Bool

        /// Its parent, `nil` at the root or when it is not in the document.
        var parent: String?
    }

    /// How many entries the revision and expansion caches have stored so far.
    private var cacheWrites: Int {
        (_revisionCache?.writes ?? 0) &+ (_expansionCache?.writes ?? 0)
    }

    /// The nodes an editing operation touches.
    ///
    /// Document-level operations — variables, imports, theme axes, the root's own
    /// properties — touch no node.
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
            // ``detachRef(_:)`` widens this to the subtree it removes and the one it
            // inserts.
            [op.refNodeID]
        case .addVariable, .removeVariable, .updateVariable,
             .addImport, .removeImport, .updateImport,
             .addThemeAxis, .removeThemeAxis, .updateThemeAxis,
             .setDocumentProperties:
            []
        }
    }

    /// The nodes a CRDT mutation touches.
    ///
    /// Remote operations reach the flat store only as ``DocumentMutation``s, and
    /// ``CRDTDocument`` emits one for *every* parent relationship a move changed,
    /// so weighing each mutation covers the reparenting that
    /// ``reconcileChildrenWithParents(after:)`` then re-derives from it — which names
    /// its own subjects for what it changes besides.
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
