//
//  EditableDocument+ComponentGraphEdit.swift
//  Woodcase
//

import Foundation

/// What an operation would change in the component graph, for the loop guard.
extension EditableDocument {
    /// Whether an operation could add an edge to the component graph, read without
    /// building anything: it places an instance or a component, writes a `ref` target or
    /// `reusable`, or writes override content naming a component. A nudge, a fill, a
    /// rename or a plain insert answers `false`, and pays for nothing else.
    ///
    /// - Parameter operation: The operation, against the document as it stands.
    /// - Returns: `false` when the operation cannot close a component loop.
    func canAddComponentEdge(_ operation: EditOperation) -> Bool {
        switch operation {
        case let .insertNode(op):
            ComponentGraphEdit.mayAddEdges(op.node)
        case let .replaceSubtree(op):
            ComponentGraphEdit.mayAddEdges(op.node)
        case let .moveNode(op):
            holdsInstanceOrComponent(op.nodeID)
        case let .setProperties(op):
            op.properties.contains(where: Self.canAddComponentEdge(path:value:))
        case let .updateKind(op):
            if case .ref = op.kind { true } else { false }
        case let .updateCommon(op):
            op.common.reusable == true && nodes[op.nodeID]?.common.reusable != true
        case let .overrideDescendant(op):
            Self.namesRef(.dictionary(op.properties))
        case let .overrideRoot(op):
            Self.namesRef(.dictionary(op.properties))
        default:
            false
        }
    }

    /// The overlay an operation lays over the component graph, or `nil` when it cannot
    /// add an edge — it places no instance, no component and no override content naming
    /// one.
    ///
    /// - Parameter operation: An operation otherwise valid against the document.
    /// - Returns: The overlay.
    func componentGraphEdit(for operation: EditOperation) -> ComponentGraphEdit? {
        guard canAddComponentEdge(operation) else { return nil }
        var edit = ComponentGraphEdit()
        switch operation {
        case let .insertNode(op):
            edit.insert(op.node, under: op.parentID)
            if let parentID = op.parentID {
                edit.children[parentID] = (children[parentID] ?? []) + [op.node.id]
            }
        case let .moveNode(op):
            if let oldParent = parents[op.nodeID] {
                edit.children[oldParent] = (children[oldParent] ?? []).filter { $0 != op.nodeID }
            }
            if let newParent = op.newParentID {
                edit.children[newParent] = (edit.children[newParent] ?? children[newParent] ?? []) + [op.nodeID]
            }
            edit.parents[op.nodeID] = .some(op.newParentID)
            edit.sites = [op.nodeID]
        case let .replaceSubtree(op):
            for id in descendantIDs(of: op.node.id) {
                edit.nodes[id] = .some(nil)
            }
            edit.insert(op.node, under: parents[op.node.id])
        case let .setProperties(op):
            guard let (old, new) = try? patchedNode(for: op) else { return nil }
            return patchEdit(of: op.nodeID, from: old, to: new)
        case let .updateKind(op):
            guard let old = nodes[op.nodeID] else { return nil }
            var new = old
            new.kind = op.kind.withEmptyChildren()
            return patchEdit(of: op.nodeID, from: old, to: new)
        case let .updateCommon(op):
            guard let old = nodes[op.nodeID] else { return nil }
            var new = old
            new.common = op.common
            return patchEdit(of: op.nodeID, from: old, to: new)
        case let .overrideDescendant(op):
            return overrideEdit(of: op.refNodeID, writing: op.properties)
        case let .overrideRoot(op):
            return overrideEdit(of: op.refNodeID, writing: op.properties)
        default:
            return nil
        }
        return edit
    }

    /// The overlay of a node rewritten in place, or `nil` when the rewrite renders
    /// nothing new and makes no component.
    private func patchEdit(of nodeID: String, from old: PenNode, to new: PenNode) -> ComponentGraphEdit? {
        let becomesComponent = new.common.reusable == true && old.common.reusable != true
        let rendersMore = !Set(new.renderedComponentIDs).isSubset(of: old.renderedComponentIDs)
        guard becomesComponent || rendersMore else { return nil }
        var edit = ComponentGraphEdit()
        edit.nodes[nodeID] = .some(PenNode(id: new.id, common: new.common, kind: new.kind.withEmptyChildren(), extras: new.extras))
        edit.sites = [nodeID]
        return edit
    }

    /// The overlay of an override about to be written onto a `ref`, or `nil` when it
    /// names no component.
    private func overrideEdit(of refNodeID: String, writing properties: [String: AnyCodable]) -> ComponentGraphEdit? {
        let probe = PenNode(
            id: refNodeID, common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "", rootOverrides: properties))
        )
        let named = probe.renderedComponentIDs.filter { !$0.isEmpty }
        guard !named.isEmpty else { return nil }
        var edit = ComponentGraphEdit()
        edit.rendered[refNodeID] = named
        edit.sites = [refNodeID]
        return edit
    }

    /// Whether one property write could add a component edge: a `ref` target, `reusable`
    /// set, a retype to `ref`, or any value — overrides, slot content, a whole kind —
    /// holding an object with a string `ref`.
    private static func canAddComponentEdge(path: String, value: AnyCodable) -> Bool {
        switch path.split(separator: ".").last.map(String.init) ?? path {
        case "ref": true
        case "reusable": value == .bool(true)
        case "type": value == .string("ref")
        default: namesRef(value)
        }
    }

    /// Whether a node, or anything under it, is an instance or a component.
    func holdsInstanceOrComponent(_ nodeID: String) -> Bool {
        descendantIDs(of: nodeID).contains { id in
            guard let node = nodes[id] else { return false }
            if node.common.reusable == true { return true }
            if case .ref = node.kind { return true }
            return false
        }
    }

    /// Whether a value holds an object with a string `ref`, at any depth.
    private static func namesRef(_ value: AnyCodable) -> Bool {
        var pending = [value]
        while let next = pending.popLast() {
            switch next {
            case let .dictionary(fields):
                if case .string? = fields["ref"] { return true }
                pending += fields.values
            case let .array(items):
                pending += items
            default:
                continue
            }
        }
        return false
    }
}
