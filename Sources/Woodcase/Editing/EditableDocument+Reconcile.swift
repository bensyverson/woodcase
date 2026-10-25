//
//  EditableDocument+Reconcile.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Ensures the ``children`` map is consistent with the ``parents`` map.
    ///
    /// After tree move operations, the list CRDTs (RGA) may have accepted
    /// operations that the tree move CRDT rejected. This method removes
    /// nodes from children lists that don't match their actual parent,
    /// and ensures each node appears in its correct parent's children list.
    ///
    /// This whole-document pass is the definition a remote batch's own reconciliation,
    /// ``reconcileChildrenWithParents(after:)``, reproduces over what the batch wrote, and
    /// the oracle the reconciliation fuzz holds it to. It names no subjects — it may
    /// reparent or reorder anywhere in the document — so it drops the whole revision and
    /// expansion caches. Only a local edit the CRDT logged but the flat store refused,
    /// which ``applyLocal(_:)`` guards against, still runs it.
    func reconcileChildrenWithParents() {
        var journal = FlatStoreJournal()
        reconcileWholeDocument(journal: &journal)
    }

    /// The whole-document pass, noting in a journal every parent link, children list and
    /// root order it changes, so a probe reading the journal sees them.
    ///
    /// - Parameter journal: The journal of the change the pass closes.
    func reconcileWholeDocument(journal: inout FlatStoreJournal) {
        _placementUnsettled = false
        _revisionCache?.invalidateAll()
        _expansionCache?.invalidateAll()
        if let crdtDocument {
            reconcileCRDT(crdtDocument, journal: &journal)
        } else {
            reconcileNonCRDT()
        }
    }

    /// CRDT-mode reconciliation. Uses the tree move CRDT as the authoritative
    /// source for parent assignments and RGA lists for ordering.
    private func reconcileCRDT(_ crdtDocument: CRDTDocument, journal: inout FlatStoreJournal) {
        // Step 1: Determine the correct parent for every live node.
        // Sources of truth (in priority order):
        //   1. Tree move CRDT parentMap — authoritative for any node it knows about
        //   2. Flat store parents — for newly created nodes not yet moved
        // Constraints:
        //   - Tombstoned parents are treated as nil (promote to root)
        //   - Parents not in the nodes dict are treated as nil
        for nodeID in nodes.keys {
            let resolvedParent: String? = if let treeEntry = crdtDocument.treeMove.parentMap[nodeID] {
                // Tree CRDT knows about this node
                if let parentID = treeEntry,
                   !crdtDocument.tombstones.contains(parentID),
                   nodes[parentID] != nil
                {
                    parentID
                } else {
                    nil
                }
            } else if let flatParent = parents[nodeID],
                      !crdtDocument.tombstones.contains(flatParent),
                      nodes[flatParent] != nil
            {
                // Not in tree CRDT (newly created, never moved) — use flat store
                flatParent
            } else {
                nil
            }

            if parents[nodeID] != resolvedParent {
                journal.noteParent(of: nodeID, in: self)
                parents[nodeID] = resolvedParent
            }
        }

        // Step 2: Build expected state from the corrected parents
        var expectedChildSets: [String: Set<String>] = [:]
        var expectedRootSet = Set<String>()

        for nodeID in nodes.keys {
            if let parentID = parents[nodeID] {
                expectedChildSets[parentID, default: []].insert(nodeID)
            } else {
                expectedRootSet.insert(nodeID)
            }
        }

        // Step 3: Rebuild rootOrder from RGA, filtered and deduplicated
        let rgaRoot = crdtDocument.childrenLists[CRDTDocument.rootListID]?.elements ?? []
        var seenRoot = Set<String>()
        var newRootOrder = rgaRoot.filter { nodeID in
            expectedRootSet.contains(nodeID) && seenRoot.insert(nodeID).inserted
        }
        // Deterministic fallback: sort root nodes not covered by the RGA
        // so that all peers produce the same order.
        for nodeID in expectedRootSet.sorted() where !seenRoot.contains(nodeID) {
            newRootOrder.append(nodeID)
        }
        if rootOrder != newRootOrder {
            journal.noteChildren(of: nil, in: self)
            rootOrder = newRootOrder
        }

        // Step 4: Rebuild children maps from per-parent RGA lists
        var newChildren: [String: [String]] = [:]
        for (listID, list) in crdtDocument.childrenLists where listID != CRDTDocument.rootListID {
            guard let expectedSet = expectedChildSets[listID] else { continue }
            var seen = Set<String>()
            let ordered = list.elements.filter { childID in
                expectedSet.contains(childID) && seen.insert(childID).inserted
            }
            if !ordered.isEmpty {
                newChildren[listID] = ordered
            }
            expectedChildSets[listID] = expectedSet.subtracting(seen)
        }
        // Handle children not covered by RGA lists (sorted for determinism)
        for (parentID, remaining) in expectedChildSets where !remaining.isEmpty {
            for childID in remaining.sorted() {
                newChildren[parentID, default: []].append(childID)
            }
        }
        // A live container that declared a children array keeps one, empty or not, so
        // a peer that removed the last child and the peers it told agree on the bytes.
        for parentID in children.keys where newChildren[parentID] == nil && nodes[parentID] != nil {
            newChildren[parentID] = []
        }
        for parentID in Set(children.keys).union(newChildren.keys) where children[parentID] != newChildren[parentID] {
            journal.noteChildren(of: parentID, in: self)
        }
        children = newChildren
    }

    /// Non-CRDT reconciliation. Simple filter and ensure consistency.
    private func reconcileNonCRDT() {
        for (nodeID, parentID) in parents {
            if nodes[parentID] == nil {
                parents[nodeID] = nil
            }
        }

        var expectedChildSets: [String: Set<String>] = [:]
        var expectedRootSet = Set<String>()
        for nodeID in nodes.keys {
            if let parentID = parents[nodeID] {
                expectedChildSets[parentID, default: []].insert(nodeID)
            } else {
                expectedRootSet.insert(nodeID)
            }
        }

        for (parentID, childIDs) in children {
            guard nodes[parentID] != nil else {
                children[parentID] = nil
                continue
            }
            // An emptied list stays declared, as it does for a local delete or move.
            var seen = Set<String>()
            children[parentID] = childIDs.filter { parents[$0] == parentID && seen.insert($0).inserted }
        }

        var seenRoot = Set<String>()
        rootOrder = rootOrder.filter { nodeID in
            parents[nodeID] == nil && nodes[nodeID] != nil && seenRoot.insert(nodeID).inserted
        }

        for (parentID, childSet) in expectedChildSets {
            for childID in childSet {
                if children[parentID] == nil {
                    children[parentID] = [childID]
                } else if !children[parentID]!.contains(childID) {
                    children[parentID]!.append(childID)
                }
            }
        }
        for nodeID in expectedRootSet where !rootOrder.contains(nodeID) {
            rootOrder.append(nodeID)
        }
    }
}
