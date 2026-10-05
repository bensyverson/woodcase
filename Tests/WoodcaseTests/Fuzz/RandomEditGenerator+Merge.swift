//
//  RandomEditGenerator+Merge.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The merge set: the operations a three-way merge has to reproduce, weighted toward
/// the ones its sequencer finds hardest — retypes, declared-empty child lists and
/// tables, reparenting to explicit indices, and components deleted under their
/// instances.
extension RandomEditGenerator {
    /// Draws one operation from the merge set, or `nil` when the draw finds nothing to
    /// act on.
    ///
    /// - Parameters:
    ///   - doc: The document the operation is meant for.
    ///   - label: A short side label, folded into the ids and names the operation mints.
    ///     Two sides drawing with one label mint the same ids — both adding a node.
    ///   - index: The operation's position in the side's run, folded in the same way.
    ///   - scope: When set, every operation stays strictly inside this node's subtree —
    ///     no document-level edits, nothing moved out, the scope root itself untouched —
    ///     so two sides given disjoint scopes never touch the same thing.
    mutating func mergeOperation(for doc: EditableDocument, label: String, index: Int, scope: String? = nil) -> EditOperation? {
        let nodeIDs = scope.map { Array(doc.descendantIDs(of: $0).dropFirst()).sorted() } ?? Array(doc.allNodeIDs).sorted()
        let newID = "\(label)_m\(index)"
        let operation: EditOperation? = switch Int.random(in: 0 ..< 20, using: &rng) {
        case 0, 1: insertLeaf(id: newID, in: doc, nodeIDs: nodeIDs, scope: scope)
        case 2: insertFrame(id: newID, in: doc, nodeIDs: nodeIDs, scope: scope)
        case 3: insertInstance(id: newID, in: doc, nodeIDs: nodeIDs, scope: scope)
        case 4, 5: delete(in: doc, nodeIDs: nodeIDs)
        case 6, 7: reparent(in: doc, nodeIDs: nodeIDs, scope: scope)
        case 8, 9: patchProperties(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 10: patchExtra(in: doc, nodeIDs: nodeIDs)
        case 11, 12: retype(in: doc, nodeIDs: nodeIDs)
        case 13: redeclareChildren(in: doc, nodeIDs: nodeIDs)
        case 14: makeReusable(in: doc, nodeIDs: nodeIDs)
        case 15: overrideInstance(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 16: detachRef(in: doc, nodeIDs: nodeIDs)
        case 17 where scope == nil: documentEntryEdit(in: doc)
        case 18 where scope == nil: documentPropertyEdit(in: doc, label: label, index: index)
        case 19 where scope == nil && !nodeIDs.isEmpty: move(in: doc, nodeIDs: nodeIDs)
        default: patchProperties(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        }
        return closesComponentCycle(operation, in: doc) ? nil : operation
    }

    /// Whether an insert or move would put an instance of a component inside that
    /// component, directly or through others.
    private func closesComponentCycle(_ operation: EditOperation?, in doc: EditableDocument) -> Bool {
        switch operation {
        case let .insertNode(insert):
            guard case let .ref(data) = insert.node.kind else { return false }
            return closesComponentCycle(adding: [data.ref], under: insert.parentID, in: doc)
        case let .moveNode(move):
            return closesComponentCycle(adding: instanceTargets(under: move.nodeID, in: doc), under: move.newParentID, in: doc)
        default:
            return false
        }
    }

    // MARK: - Structure

    /// A random container to put a node under: inside `scope` when set, else sometimes
    /// the top level (`nil`).
    private mutating func parent(in doc: EditableDocument, nodeIDs: [String], scope: String?, excluding: String? = nil) -> String? {
        let candidates = ((scope.map { [$0] } ?? []) + containers(in: doc, among: nodeIDs)).filter { $0 != excluding }
        if scope == nil, candidates.isEmpty || Int.random(in: 0 ..< 3, using: &rng) == 0 {
            return nil
        }
        return candidates.randomElement(using: &rng) ?? scope
    }

    /// Inserts a rectangle, text or ellipse, sometimes at an explicit index.
    private mutating func insertLeaf(id: String, in doc: EditableDocument, nodeIDs: [String], scope: String?) -> EditOperation? {
        let parentID = parent(in: doc, nodeIDs: nodeIDs, scope: scope)
        let node = PenNode(id: id, common: PenNodeCommon(name: id), kind: leafKind())
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: maybeIndex(in: doc, parentID: parentID)))
    }

    /// Inserts a frame that declares an empty child list, leaves the key out, or holds
    /// a child.
    private mutating func insertFrame(id: String, in doc: EditableDocument, nodeIDs: [String], scope: String?) -> EditOperation? {
        let parentID = parent(in: doc, nodeIDs: nodeIDs, scope: scope)
        let children: [PenNode]? = switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0: []
        case 1: nil
        default: [PenNode(id: "\(id)c", common: PenNodeCommon(name: "\(id)c"), kind: leafKind())]
        }
        let node = PenNode(id: id, common: PenNodeCommon(name: id), kind: .frame(PenNode.FrameData(
            width: .fixed(Double(Int.random(in: 1 ... 40, using: &rng) * 10)), children: children
        )))
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: maybeIndex(in: doc, parentID: parentID)))
    }

    /// Inserts an instance of a random component.
    private mutating func insertInstance(id: String, in doc: EditableDocument, nodeIDs: [String], scope: String?) -> EditOperation? {
        let components = nodeIDs.filter { doc.nodes[$0]?.common.reusable == true }
        guard let component = components.randomElement(using: &rng) else { return nil }
        let parentID = parent(in: doc, nodeIDs: nodeIDs, scope: scope)
        let node = PenNode(id: id, common: PenNodeCommon(name: id), kind: .ref(PenNode.RefData(ref: component)))
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID))
    }

    /// Deletes a random node; a component goes with its instances detached half the time,
    /// and is refused while one survives the other half.
    private mutating func delete(in _: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        guard let nodeID = nodeIDs.randomElement(using: &rng) else { return nil }
        let instances: EditOperation.DeleteNode.Instances = Bool.random(using: &rng) ? .detach : .refuse
        return .deleteNode(EditOperation.DeleteNode(nodeID: nodeID, instances: instances))
    }

    /// Moves a random node under a random container, sometimes to an explicit index.
    private mutating func reparent(in doc: EditableDocument, nodeIDs: [String], scope: String?) -> EditOperation? {
        guard let nodeID = nodeIDs.randomElement(using: &rng) else { return nil }
        let parentID = parent(in: doc, nodeIDs: nodeIDs, scope: scope, excluding: nodeID)
        return .moveNode(EditOperation.MoveNode(nodeID: nodeID, newParentID: parentID, index: maybeIndex(in: doc, parentID: parentID)))
    }

    /// A random leaf kind with a random width.
    mutating func leafKind() -> PenNode.Kind {
        let width = PenSizing.fixed(Double(Int.random(in: 1 ... 40, using: &rng) * 5))
        return switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0: .rectangle(PenNode.RectangleData(width: width))
        case 1: .text(PenNode.TextData(width: width))
        default: .ellipse(PenNode.EllipseData(width: width))
        }
    }
}
