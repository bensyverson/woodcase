//
//  EditPlanner+Routing.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// The edits that store values an editor computed for what is drawn at `target`, wherever
    /// each one is stored.
    ///
    /// A canvas gesture — a move, a resize, a turn, a scale — knows the values it wants a node
    /// to draw with, not where the format keeps them. This is that decision, so every
    /// editor and ``ScaleCapture`` make it the same way:
    ///
    /// | Target | Where the values go |
    /// |---|---|
    /// | a node with storage of its own | one `setProperties` on the node |
    /// | an instance root (a `ref` node) | its `common.` properties (`x`, `y`, `flipX`, …) on the `ref` node; the rest as root overrides (``EditIntent/override(_:unset:)``) |
    /// | a node inside an instance, a nested instance's root among them | an override on the outermost instance (``EditIntent/override(_:unset:)``) |
    ///
    /// The component itself never changes.
    ///
    /// A write on a node's own storage is **not** planned: the caller vouches for its values
    /// — they are values the node already draws, moved, sized or turned — so the planner's
    /// value checks have nothing to refuse, and skipping them keeps a live gesture cheap
    /// enough to run every display refresh. A deep `common.metadata.<key>` path is still
    /// folded onto the metadata the node carries (``EditOperation/normalized(in:)``), so the
    /// edit applies as it stands. A value that wants checking is a ``EditIntent/set(_:)``
    /// planned with ``plan(_:at:in:)-(_,ResolvedNodeAddress,_)``, and an inspector's intent —
    /// a value to check, a bind, an unbind — with ``plan(_:routedAt:in:)``, which stores each
    /// property where this does.
    ///
    /// Every override is planned, so paths become the raw keys the instance stores and the
    /// planner's refusals hold — an `x` on a node its instance's layout places is refused.
    ///
    /// ```swift
    /// let operations = try EditPlanner.routeWrites(["common.x": 40, "kind.width": 240], at: .node(id: "Chip"), in: document)
    /// // [.setProperties(Chip: common.x), .overrideRoot(Chip: width)]
    /// ```
    ///
    /// - Parameters:
    ///   - properties: The values, by property path. Empty writes nothing.
    ///   - target: What is drawn with them.
    ///   - document: The document the edits will be applied to, as it stands.
    /// - Returns: The edits, own writes first; none for no properties.
    /// - Throws: The ``EditRefusal`` the planner raises for an override.
    static func routeWrites(
        _ properties: [String: AnyCodable], at target: ResolvedNodeAddress, in document: EditableDocument
    ) throws(EditRefusal) -> [EditOperation] {
        guard !properties.isEmpty else { return [] }
        let (own, overridden) = Holder(target, in: document).split(properties)
        var operations: [EditOperation] = []
        if !own.isEmpty {
            operations.append(ownWrite(own, on: target.targetID, in: document))
        }
        if !overridden.isEmpty {
            operations += try plan(.override(overridden), at: target, in: document).operations
        }
        return operations
    }
}

private extension EditPlanner {
    /// A `setProperties` on a node's own storage, its deep metadata keys and natural paths
    /// (`kind.blendMode`) folded onto the metadata the node carries, as the planner folds them.
    static func ownWrite(
        _ properties: [String: AnyCodable], on id: String, in document: EditableDocument
    ) -> EditOperation {
        let write = EditOperation.setProperties(EditOperation.SetProperties(nodeID: id, properties: properties))
        let folds = properties.keys.contains { $0.hasPrefix(metadataPrefix) }
            || document.node(id: id).map { NodePropertyCodec.writesNaturalPath(properties, on: $0.kind) } == true
        return folds ? write.normalized(in: document) : write
    }

    /// The prefix of a deep metadata key.
    static let metadataPrefix = "common.metadata."
}
