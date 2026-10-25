//
//  EditableDocument+RemoteReconcile.swift
//  Woodcase
//

import Foundation

/// The reconciliation that closes a remote batch, settled over what the batch wrote.
///
/// ``reconcileChildrenWithParents()`` re-derives every parent link and every children
/// list from the CRDT, which costs the whole document per batch — and a collaborator's
/// recolor is a batch. But when the flat store a batch starts from already agrees with
/// the CRDT, only what the batch touched can disagree afterwards: the nodes whose parent
/// link it wrote, created or removed (and the children a created or removed node takes or
/// leaves), the lists it wrote, the lists those nodes leave and join, and the root order.
/// The ``FlatStoreJournal`` names all of them. This settles exactly those, by the same
/// rules the whole-document pass applies, and leaves everything else alone — so it agrees
/// with the whole-document pass on every key, which the reconciliation fuzz checks after
/// every batch.
///
/// A local edit can leave the flat store disagreeing with the CRDT: an index the lists
/// cannot give (a list holding live entries the flat store does not). The local author keeps the edit as made, as
/// before; ``applyLocal(_:)`` checks the edit's own footprint and, when it disagrees,
/// marks the store unsettled (`_placementUnsettled`), and the next remote batch runs the
/// whole-document pass once instead — which is when the store used to catch up with the
/// CRDT anyway.
extension EditableDocument {
    /// The placement a footprint settles to, where it differs from the flat store.
    struct SettledPlacement {
        /// Nodes whose parent link changes, with the new parent.
        var parents: [String: String?] = [:]

        /// Parents whose children list changes, with the new list: `nil` for none.
        var children: [String: [String]?] = [:]

        /// The new root order, when it changes.
        var rootOrder: [String]?

        /// Whether the flat store already agrees.
        var isEmpty: Bool {
            parents.isEmpty && children.isEmpty && rootOrder == nil
        }

        /// The nodes a cache rule must weigh: every node placed and every list rewritten.
        var subjects: [String] {
            Array(parents.keys) + Array(children.keys)
        }
    }

    /// Settles the placement a remote batch touched against the CRDT, noting every write
    /// in the journal and keeping the caches in step.
    ///
    /// A batch that moved nothing — property writes, document tables — returns at once.
    /// A batch that created or removed a node also reads the tree CRDT's parent map once,
    /// for the nodes that name it as their parent, which nothing else indexes. A store a
    /// local edit left unsettled is reconciled whole, once.
    ///
    /// - Parameter journal: The batch's journal, which this extends with its own writes.
    func reconcileChildrenWithParents(after journal: inout FlatStoreJournal) {
        guard let crdtDocument else { return reconcileChildrenWithParents() }
        if _placementUnsettled {
            return reconcileWholeDocument(journal: &journal)
        }
        guard !journal.movesNothing(in: self) else { return }
        let settled = settledPlacement(after: journal, crdt: crdtDocument)
        guard !settled.isEmpty else { return }
        invalidatingCaches(touching: settled.subjects) {
            for (nodeID, parent) in settled.parents {
                journal.noteParent(of: nodeID, in: self)
                parents[nodeID] = parent
            }
            for (parentID, list) in settled.children {
                journal.noteChildren(of: parentID, in: self)
                children[parentID] = list
            }
            if let order = settled.rootOrder {
                journal.noteChildren(of: nil, in: self)
                rootOrder = order
            }
        }
    }

    /// Marks the store unsettled when a local edit left its footprint disagreeing with
    /// the CRDT, so the next remote batch reconciles the whole document.
    ///
    /// - Parameter journal: The local edit's footprint.
    func notePlacementAfterLocalEdit(_ journal: FlatStoreJournal) {
        guard let crdtDocument, !_placementUnsettled, !journal.movesNothing(in: self) else { return }
        if !settledPlacement(after: journal, crdt: crdtDocument).isEmpty {
            _placementUnsettled = true
        }
    }

    /// What the footprint a journal names settles to, where that differs from the store.
    private func settledPlacement(after journal: FlatStoreJournal, crdt: CRDTDocument) -> SettledPlacement {
        let moved = nodesToPlace(after: journal, crdt: crdt)
        var settled = SettledPlacement()
        var resolved: [String: String?] = [:]
        var arrivals: [String?: [String]] = [:]
        var lists = Set(journal.children.keys)
        var touchesRoot = journal.rootOrder != nil
        for (id, before) in journal.nodes where (before == nil) != (nodes[id] == nil) || crdt.tombstones.contains(id) {
            lists.insert(id)
        }
        for nodeID in moved {
            if let parentBefore = parents[nodeID] { lists.insert(parentBefore) } else { touchesRoot = true }
            guard nodes[nodeID] != nil else { continue }
            let parent = resolvedParent(of: nodeID, crdt: crdt)
            resolved[nodeID] = .some(parent)
            arrivals[parent, default: []].append(nodeID)
            if let parent { lists.insert(parent) } else { touchesRoot = true }
            if parents[nodeID] != parent { settled.parents[nodeID] = .some(parent) }
        }
        let parent: (String) -> String? = { nodeID in resolved[nodeID] ?? self.parents[nodeID] }
        for parentID in lists {
            let list = settledChildren(of: parentID, journal: journal, arrivals: arrivals[parentID] ?? [], crdt: crdt, parent: parent)
            if children[parentID] != list { settled.children[parentID] = .some(list) }
        }
        if touchesRoot {
            let order = settledRootOrder(journal: journal, arrivals: arrivals[nil] ?? [], crdt: crdt, parent: parent)
            if rootOrder != order { settled.rootOrder = order }
        }
        return settled
    }

    /// The nodes whose parent must be resolved again: every one whose link the journal
    /// names or that it created, the children a removed or tombstoned node leaves, and
    /// every node the tree CRDT places under such a node.
    private func nodesToPlace(after journal: FlatStoreJournal, crdt: CRDTDocument) -> Set<String> {
        var moved = Set(journal.parents.keys)
        var parentsChanged = Set<String>()
        for (id, before) in journal.nodes {
            let created = before == nil && nodes[id] != nil
            let removed = before != nil && nodes[id] == nil
            // A node its existence register says is deleted can no longer hold the
            // children it had.
            guard created || removed || crdt.tombstones.contains(id) else { continue }
            if created { moved.insert(id) }
            parentsChanged.insert(id)
            if let leaving = journal.children[id] ?? nil { moved.formUnion(leaving) }
            if let holding = children[id] { moved.formUnion(holding) }
        }
        guard !parentsChanged.isEmpty else { return moved }
        for (nodeID, parent) in crdt.treeMove.parentMap {
            if let parent, parentsChanged.contains(parent) { moved.insert(nodeID) }
        }
        return moved
    }

    /// A node's parent as the CRDT settles it: the tree CRDT's, or for a node it has never
    /// placed the flat store's — either only while that parent is alive.
    private func resolvedParent(of nodeID: String, crdt: CRDTDocument) -> String? {
        let candidate: String? = if let entry = crdt.treeMove.parentMap[nodeID] { entry } else { parents[nodeID] }
        guard let candidate, !crdt.tombstones.contains(candidate), nodes[candidate] != nil else { return nil }
        return candidate
    }

    /// A parent's children as the CRDT orders them: its list's live members that name it
    /// as their parent, then any it holds that the list does not, sorted; `[]` for a
    /// parent that declared a list and holds nothing, `nil` for one that never did or is
    /// gone.
    private func settledChildren(
        of parentID: String,
        journal: FlatStoreJournal,
        arrivals: [String],
        crdt: CRDTDocument,
        parent: (String) -> String?
    ) -> [String]? {
        guard nodes[parentID] != nil else { return nil }
        let listed = crdt.childrenLists[parentID]?.elements ?? []
        let candidates = ((journal.children[parentID] ?? nil) ?? []) + (children[parentID] ?? []) + listed + arrivals
        let ordered = order(candidates, listed: listed) { parent($0) == parentID }
        return ordered.isEmpty ? (children[parentID] == nil ? nil : []) : ordered
    }

    /// The root order as the CRDT gives it, by the same rule as a children list.
    private func settledRootOrder(
        journal: FlatStoreJournal,
        arrivals: [String],
        crdt: CRDTDocument,
        parent: (String) -> String?
    ) -> [String] {
        let listed = crdt.childrenLists[CRDTDocument.rootListID]?.elements ?? []
        let candidates = (journal.rootOrder ?? []) + rootOrder + listed + arrivals
        return order(candidates, listed: listed) { parent($0) == nil }
    }

    /// The live candidates a parent holds, in the list's order and then sorted.
    private func order(_ candidates: [String], listed: [String], holds: (String) -> Bool) -> [String] {
        let expected = Set(candidates.filter { nodes[$0] != nil && holds($0) })
        var seen = Set<String>()
        let ordered = listed.filter { expected.contains($0) && seen.insert($0).inserted }
        return ordered + expected.subtracting(seen).sorted()
    }
}
