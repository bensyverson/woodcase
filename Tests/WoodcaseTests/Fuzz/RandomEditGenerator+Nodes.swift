//
//  RandomEditGenerator+Nodes.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The CRDT set's node operations: inserts, moves, common-property edits and the
/// contended "hot" containers.
extension RandomEditGenerator {
    /// Inserts a rectangle, text or ellipse at the top level or under a random container.
    mutating func insertLeaf(in doc: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        let newID = "\(label)_ins_\(index)"
        let parentCandidates = containers(in: doc, among: nodeIDs)
        let parentID: String? = if parentCandidates.isEmpty {
            nil
        } else if Bool.random(using: &rng) {
            parentCandidates.randomElement(using: &rng)
        } else {
            nil
        }
        let common = PenNodeCommon(name: "Fuzz_\(newID)")
        let node = switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0:
            PenNode(id: newID, common: common, kind: .rectangle(PenNode.RectangleData(width: .fixed(Double.random(in: 10 ... 200, using: &rng)))))
        case 1:
            PenNode(id: newID, common: common, kind: .text(PenNode.TextData(width: .fixed(Double.random(in: 50 ... 300, using: &rng)))))
        default:
            PenNode(id: newID, common: common, kind: .ellipse(PenNode.EllipseData(width: .fixed(Double.random(in: 20 ... 150, using: &rng)))))
        }
        let at = maybeIndex(in: doc, parentID: parentID)
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: at))
    }

    /// Inserts a frame or group holding one rectangle — a subtree insert.
    mutating func insertContainer(in doc: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        let newID = "\(label)_ins_\(index)"
        let childID = "\(label)_ins_\(index)c"
        let parentCandidates = containers(in: doc, among: nodeIDs)
        let parentID: String? = if parentCandidates.isEmpty || Bool.random(using: &rng) {
            nil
        } else {
            parentCandidates.randomElement(using: &rng)
        }
        let child = PenNode(
            id: childID,
            common: PenNodeCommon(name: "FuzzChild_\(childID)"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(Double.random(in: 10 ... 100, using: &rng))))
        )
        let common = PenNodeCommon(name: "Fuzz_\(newID)")
        let node = if Bool.random(using: &rng) {
            PenNode(id: newID, common: common, kind: .frame(PenNode.FrameData(
                width: .fixed(Double.random(in: 100 ... 500, using: &rng)), children: [child]
            )))
        } else {
            PenNode(id: newID, common: common, kind: .group(PenNode.GroupData(children: [child])))
        }
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID))
    }

    /// Moves a random node to the top level or under a random container, sometimes to an
    /// explicit index.
    mutating func move(in doc: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        let nodeID = nodeIDs.randomElement(using: &rng)!
        let parentCandidates = containers(in: doc, among: nodeIDs).filter { $0 != nodeID }
        let newParentID: String? = if parentCandidates.isEmpty || Bool.random(using: &rng) {
            nil
        } else {
            parentCandidates.randomElement(using: &rng)
        }
        let at = maybeIndex(in: doc, parentID: newParentID)
        return .moveNode(EditOperation.MoveNode(nodeID: nodeID, newParentID: newParentID, index: at))
    }

    /// Changes one to three common properties of a random node, theme overrides included.
    mutating func updateCommon(in doc: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        let nodeID = nodeIDs.randomElement(using: &rng)!
        guard let node = doc.nodes[nodeID] else { return nil }
        var common = node.common
        for _ in 0 ..< Int.random(in: 1 ... 3, using: &rng) {
            switch Int.random(in: 0 ..< 6, using: &rng) {
            case 0: common.name = "Fuzz_\(label)_\(index)"
            case 1: common.opacity = .literal(Double.random(in: 0 ... 1, using: &rng))
            case 2: common.x = .literal(Double.random(in: -500 ... 500, using: &rng))
            case 3: common.y = .literal(Double.random(in: -500 ... 500, using: &rng))
            case 4:
                // Set a theme override on this node (exercises inherited theme resolution)
                let axes = (doc.themes?.keys).map { $0.sorted() } ?? []
                if let axis = axes.randomElement(using: &rng),
                   let options = doc.themes?[axis],
                   let option = options.randomElement(using: &rng)
                {
                    var theme = common.theme ?? [:]
                    theme[axis] = option
                    common.theme = theme
                }
            case 5:
                // Clear theme override (revert to inherited)
                common.theme = nil
            default: break
            }
        }
        return .updateCommon(EditOperation.UpdateCommon(nodeID: nodeID, common: common))
    }

    /// Moves, deletes or renames one of the base document's containers `f1`, `f2` and
    /// `g1`, which several peers are likely to contend over.
    mutating func hotNodeEdit(in doc: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        let hotID = ["f1", "f2", "g1"].randomElement(using: &rng)!
        guard doc.nodes[hotID] != nil else { return nil }
        switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0:
            let parentCandidates = containers(in: doc, among: nodeIDs).filter { $0 != hotID }
            let newParentID: String? = if parentCandidates.isEmpty || Bool.random(using: &rng) {
                nil
            } else {
                parentCandidates.randomElement(using: &rng)
            }
            return .moveNode(EditOperation.MoveNode(nodeID: hotID, newParentID: newParentID))
        case 1:
            return .deleteNode(EditOperation.DeleteNode(nodeID: hotID))
        default:
            guard let node = doc.nodes[hotID] else { return nil }
            var common = node.common
            common.name = "Hot_\(label)_\(index)"
            common.opacity = .literal(Double.random(in: 0 ... 1, using: &rng))
            return .updateCommon(EditOperation.UpdateCommon(nodeID: hotID, common: common))
        }
    }
}
