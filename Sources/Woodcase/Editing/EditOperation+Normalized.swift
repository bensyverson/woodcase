//
//  EditOperation+Normalized.swift
//  Woodcase
//

import Foundation

public extension EditOperation {
    /// The operation in the per-path vocabulary forward ops, inverses and CRDT ops share.
    ///
    /// ``updateCommon(_:)`` and an ``updateKind(_:)`` that keeps the node's type replace a
    /// whole struct, so they claim every property they carry even when most are
    /// unchanged — and an undo, a merge or another author then has to treat them all as
    /// written. This rewrites them as a ``setProperties(_:)`` of only the paths that
    /// differ from the document (found by ``PropertyDiff``), which applies to the same
    /// node.
    ///
    /// A ``setProperties(_:)`` naming a deep key — `common.metadata.woodcase.spans` —
    /// is folded onto the node's metadata by ``NodePropertyCodec/folding(_:onto:)``, the
    /// same fold the batch planner runs, so it becomes a write of the whole object with
    /// every key it does not name kept. Its keys, inverse and replication are then per
    /// metadata entry (``ChangeKey/keys(of:in:)``,
    /// ``EditableDocument/granularInverse(of:)``), so it merges with other authors'
    /// writes to sibling entries.
    ///
    /// A natural path — `kind.blendMode` — is folded the same way, into the metadata key it
    /// is stored under (``NodePropertyCodec/storingNaturalPaths(_:on:)``).
    ///
    /// Left as they are:
    /// - An ``updateKind(_:)`` that changes the node's type: there is no path for
    ///   "become a text node", so it stays whole (its key is
    ///   ``ChangeKey/property(node:path:)`` with ``ChangeKey/wholeKindPath``).
    /// - An ``updateKind(_:)`` whose ``UpdateKind/emptyChildren`` changes whether an
    ///   empty container declares `"children": []` — no property path says that.
    /// - An operation on a node the document does not hold, which ``EditableDocument/apply(_:)``
    ///   will refuse in its own words.
    /// - A rewrite the property codec cannot reproduce exactly. The patch is checked
    ///   against the node the original would produce, so a gap in the path vocabulary
    ///   costs granularity, never correctness.
    /// - Every other case.
    ///
    /// ```swift
    /// let op = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "r1", common: renamed))
    /// op.normalized(in: document)   // .setProperties(["common.name": "Renamed"])
    /// ```
    ///
    /// - Parameter document: The document the operation is about to be applied to.
    /// - Returns: The equivalent per-path operation, or `self`.
    func normalized(in document: EditableDocument) -> EditOperation {
        normalized(in: document, nodeAt: { document.nodes[$0] })
    }

    /// The operation normalized against the document with some nodes standing in for stored ones.
    ///
    /// ``normalized(in:)`` is this with the document's own nodes. A preview
    /// (``EditableDocument/previewNodes(for:)``) passes the nodes earlier operations of
    /// the same batch would have left, so each operation normalizes against what a commit
    /// would have stored by then, and the preview and the commit share this one fold.
    ///
    /// - Parameters:
    ///   - document: The document the operation is about to be applied to; its child
    ///     lists settle whether an `updateKind` changes declared-ness.
    ///   - lookup: The stored node an id names at this point, or `nil` for none.
    /// - Returns: The equivalent per-path operation, or `self`.
    internal func normalized(in document: EditableDocument, nodeAt lookup: (String) -> PenNode?) -> EditOperation {
        switch self {
        case let .updateCommon(op):
            guard let node = lookup(op.nodeID) else { return self }
            var target = node
            target.common = op.common
            let paths = PropertyDiff.diffCommon(old: node.common, new: op.common)
            return Self.patch(node: node, target: target, paths: paths) ?? self
        case let .updateKind(op):
            guard let node = lookup(op.nodeID) else { return self }
            // A change of declared-ness has no path; it stays whole.
            if let empty = op.emptyChildren, (document.children[op.nodeID] ?? []).isEmpty,
               (document.children[op.nodeID] != nil) != (empty == .declared)
            {
                return self
            }
            var target = node
            target.kind = op.kind.withEmptyChildren()
            let paths = PropertyDiff.diffKind(old: node.kind, new: target.kind)
            guard !paths.contains(Self.kindTypePath) else { return self }
            return Self.patch(node: node, target: target, paths: paths) ?? self
        case let .setProperties(op):
            guard let node = lookup(op.nodeID),
                  op.properties.keys.contains(where: { NodePropertyCodec.deepKey(of: $0) != nil })
                  || NodePropertyCodec.writesNaturalPath(op.properties, on: node.kind),
                  let folded = try? NodePropertyCodec.folding(op.properties, onto: node)
            else { return self }
            return .setProperties(SetProperties(nodeID: op.nodeID, properties: folded))
        default:
            return self
        }
    }
}

private extension EditOperation {
    /// The marker ``PropertyDiff/diffKind(old:new:)`` emits for a change of node type.
    static let kindTypePath = "kind.type"

    /// A patch of the given paths that turns `node` into `target`, or `nil` if the
    /// codec cannot read or write one of them, or its result differs from `target`.
    static func patch(node: PenNode, target: PenNode, paths: Set<String>) -> EditOperation? {
        var properties: [String: AnyCodable] = [:]
        var patched = node
        do {
            for path in paths {
                let value = try NodePropertyCodec.value(at: path, of: target)
                properties[path] = value
                patched = try NodePropertyCodec.setting(value, at: path, on: patched)
            }
        } catch {
            return nil
        }
        patched.kind = patched.kind.withEmptyChildren()
        guard patched == target else { return nil }
        return .setProperties(SetProperties(nodeID: node.id, properties: properties))
    }
}
