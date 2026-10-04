//
//  ChangeKey+Operation.swift
//  Woodcase
//

import Foundation

public extension ChangeKey {
    /// The keys an operation writes, computed against the document *before* it is applied.
    ///
    /// Call this where you would call ``EditableDocument/prepareInverse(of:)``: a delete's
    /// keys name every node the subtree holds, which only the document before the delete
    /// knows. Every case of ``EditOperation`` is mapped here, without a `default`, so a
    /// new case cannot ship unkeyed.
    ///
    /// - A whole-struct ``EditOperation/updateCommon(_:)`` or same-case
    ///   ``EditOperation/updateKind(_:)`` writes only the paths that differ, exactly as
    ///   ``EditOperation/normalized(in:)`` rewrites it.
    /// - A change of node type writes ``wholeKindPath`` *and* every `kind.*` path of
    ///   both kinds, so a later write to any one of them meets it.
    /// - A ``EditOperation/detachRef(_:)``, and a delete that detaches instances, write
    ///   the existence of each ref removed and of every node its expansion inserts — the
    ///   ids come from the same detach plan the operation carries out.
    /// - ``EditOperation/setDocumentProperties(_:)`` writes ``document(_:)`` per key.
    ///
    /// - Parameters:
    ///   - operation: The operation about to be applied.
    ///   - document: The document it will be applied to, as it stands.
    /// - Returns: The keys, without duplicates, in a stable order.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` when an operation that needs the
    ///   document's view of a node names one the document does not hold.
    static func keys(of operation: EditOperation, in document: EditableDocument) throws -> [ChangeKey] {
        let keys: [ChangeKey] = switch operation {
        case let .insertNode(op):
            document.collectInsertedIDs(in: op.node).map { .existence(node: $0) } + [.placement(node: op.node.id)]
        case let .deleteNode(op):
            try deleteKeys(op, in: document)
        case let .moveNode(op):
            try [.placement(node: document.requireNode(op.nodeID).id)]
        case let .replaceSubtree(op):
            try replaceKeys(op, in: document)
        case let .updateCommon(op):
            try PropertyDiff.diffCommon(old: document.requireNode(op.nodeID).common, new: op.common)
                .sorted().map { .property(node: op.nodeID, path: $0) }
        case let .updateKind(op):
            try kindKeys(nodeID: op.nodeID, old: document.requireNode(op.nodeID).kind, new: op.kind)
        case let .setProperties(op):
            op.properties.keys.sorted().map { .property(node: op.nodeID, path: $0) }
        case let .overrideDescendant(op):
            Set(op.properties.keys).union(op.unset).sorted().map {
                .override(ref: op.refNodeID, descendant: op.descendantID, key: $0)
            }
        case let .overrideRoot(op):
            Set(op.properties.keys).union(op.unset).sorted().map { .rootOverride(ref: op.refNodeID, key: $0) }
        case let .detachRef(op):
            try detachKeys(refIDs: [op.refNodeID], in: document)
        case let .addVariable(op):
            [.variable(name: op.name)]
        case let .updateVariable(op):
            [.variable(name: op.name)]
        case let .removeVariable(op):
            [.variable(name: op.name)]
        case let .addImport(op):
            [.importAlias(op.alias)]
        case let .updateImport(op):
            [.importAlias(op.alias)]
        case let .removeImport(op):
            [.importAlias(op.alias)]
        case let .addThemeAxis(op):
            [.themeAxis(op.name)]
        case let .updateThemeAxis(op):
            [.themeAxis(op.name)]
        case let .removeThemeAxis(op):
            [.themeAxis(op.name)]
        case let .setDocumentProperties(op):
            op.properties.keys.sorted().map { .document($0) }
        }
        return unique(keys)
    }

    /// The paths a property write to one node changes, as keys.
    ///
    /// - Parameters:
    ///   - nodeID: The node written.
    ///   - old: Its kind as it stands.
    ///   - new: The kind written.
    /// - Returns: The changed `kind.*` paths, or for a change of node type
    ///   ``wholeKindPath`` followed by every path of both kinds.
    internal static func kindKeys(nodeID: String, old: PenNode.Kind, new: PenNode.Kind) -> [ChangeKey] {
        let changed = PropertyDiff.diffKind(old: old, new: new)
        guard changed.contains(kindTypePath) else {
            return changed.sorted().map { .property(node: nodeID, path: $0) }
        }
        let paths = changed.subtracting([kindTypePath])
            .union(PropertyDiff.allKindKeys(old))
            .union(PropertyDiff.allKindKeys(new))
        return [.property(node: nodeID, path: wholeKindPath)]
            + paths.sorted().map { .property(node: nodeID, path: $0) }
    }

    /// A delete's keys: every node of the subtree, its root's place, and each instance
    /// a detaching delete will detach.
    private static func deleteKeys(_ op: EditOperation.DeleteNode, in document: EditableDocument) throws -> [ChangeKey] {
        _ = try document.requireNode(op.nodeID)
        var keys: [ChangeKey] = document.descendantIDs(of: op.nodeID).map { .existence(node: $0) }
        keys.append(.placement(node: op.nodeID))
        if op.instances == .detach {
            keys += try detachKeys(refIDs: document.instancesToDetach(for: op), in: document)
        }
        return keys
    }

    /// A run of detaches' keys: each ref's existence and the existence of every node its
    /// planned expansion inserts, from the same plan the detach itself carries out.
    private static func detachKeys(refIDs: [String], in document: EditableDocument) throws -> [ChangeKey] {
        try document.detachPlans(for: refIDs).flatMap { plan in
            [ChangeKey.existence(node: plan.refID)]
                + document.collectInsertedIDs(in: plan.subtree).map { .existence(node: $0) }
        }
    }

    /// A replace's keys: the root's changed properties and the existence of every
    /// descendant on either side, since all of them are swapped out.
    private static func replaceKeys(
        _ op: EditOperation.ReplaceSubtree,
        in document: EditableDocument
    ) throws -> [ChangeKey] {
        let root = try document.requireNode(op.node.id)
        var keys = PropertyDiff.diffCommon(old: root.common, new: op.node.common)
            .sorted().map { ChangeKey.property(node: root.id, path: $0) }
        keys += kindKeys(nodeID: root.id, old: root.kind, new: op.node.kind.withEmptyChildren())
        keys += Set(root.extras.values.keys).union(op.node.extras.values.keys).sorted()
            .filter { root.extras[$0] != op.node.extras[$0] }
            .map { .property(node: root.id, path: "\(NodePropertyCodec.extrasPrefix)\($0)") }
        let old = document.descendantIDs(of: root.id).dropFirst()
        let new = document.collectInsertedIDs(in: op.node).dropFirst()
        keys += Set(old).union(new).sorted().map { .existence(node: $0) }
        return keys
    }

    /// The marker ``PropertyDiff/diffKind(old:new:)`` emits for a change of node type.
    internal static let kindTypePath = "kind.type"

    /// The keys in their first-seen order, each once.
    private static func unique(_ keys: [ChangeKey]) -> [ChangeKey] {
        var seen = Set<ChangeKey>()
        return keys.filter { seen.insert($0).inserted }
    }
}
