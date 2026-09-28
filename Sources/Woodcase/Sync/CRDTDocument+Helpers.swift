//
//  CRDTDocument+Helpers.swift
//  Woodcase
//

import Foundation

extension CRDTDocument {
    // MARK: - Tree traversal helpers

    func collectNodes(in node: PenNode) -> [PenNode] {
        var result = [node]
        for childID in node.kind.childIDs {
            switch node.kind {
            case let .frame(data):
                for child in data.children ?? [] where child.id == childID {
                    result.append(contentsOf: collectNodes(in: child))
                }
            case let .group(data):
                for child in data.children ?? [] where child.id == childID {
                    result.append(contentsOf: collectNodes(in: child))
                }
            default:
                break
            }
        }
        return result
    }

    func findParentInSubtree(of childID: String, in root: PenNode) -> String? {
        let children: [PenNode]
        switch root.kind {
        case let .frame(data): children = data.children ?? []
        case let .group(data): children = data.children ?? []
        default: return nil
        }

        for child in children {
            if child.id == childID { return root.id }
            if let found = findParentInSubtree(of: childID, in: child) { return found }
        }
        return nil
    }

    func collectDescendants(of nodeID: String, document: EditableDocument) -> [String] {
        var result = [nodeID]
        for childID in document.children[nodeID] ?? [] {
            result.append(contentsOf: collectDescendants(of: childID, document: document))
        }
        return result
    }

    func findPositionID(for elementID: String, in list: RGAList<String>) -> PositionID? {
        for entry in list.entries where entry.value == elementID && !entry.isDeleted {
            return entry.positionID
        }
        return nil
    }

    /// Searches all RGA lists for a node's live entries.
    ///
    /// A node can have multiple live entries across different lists when concurrent
    /// moves place it in different parents. This returns ALL live entries so callers
    /// can tombstone all of them.
    ///
    /// This is necessary because after tree CRDT reconciliation, the flat store's
    /// `parents` map may disagree with where the node actually lives in the RGA.
    func findAllEntries(for nodeID: String) -> [(listID: String, positionID: PositionID)] {
        var results: [(listID: String, positionID: PositionID)] = []
        for (listID, list) in childrenLists {
            for entry in list.entries where entry.value == nodeID && !entry.isDeleted {
                results.append((listID, entry.positionID))
            }
        }
        return results
    }
}
