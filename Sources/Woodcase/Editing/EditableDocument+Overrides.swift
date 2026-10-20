//
//  EditableDocument+Overrides.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Applies an ``EditOperation/OverrideDescendant`` operation.
    ///
    /// Merges the given properties into the ref node's descendant overrides
    /// for the specified descendant ID, creating the override if it doesn't exist,
    /// then removes the keys the operation unsets.
    ///
    /// - Parameter op: The override operation parameters.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the ref node doesn't exist,
    ///   ``EditingError/notARefNode(id:)`` if the node is not a `ref`,
    ///   ``EditingError/overrideTargetNotFound(refID:descendantKey:candidates:)`` if
    ///   the descendant key names nothing in the component, or
    ///   ``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``
    ///   if a value is not one the node it patches can take.
    func applyOverrideDescendant(_ op: EditOperation.OverrideDescendant) throws {
        nodes[op.refNodeID] = try overriddenNode(for: op)

        // Overrides can affect expanded size — invalidate layout for the ref node
        invalidateLayoutCache(for: op.refNodeID, category: .layout)
    }

    /// The ref node an ``EditOperation/OverrideDescendant`` would store, checked as
    /// ``applyOverrideDescendant(_:)`` checks it, with nothing written.
    ///
    /// - Parameters:
    ///   - op: The override operation parameters.
    ///   - base: The ref node to merge into in place of the stored one: an earlier
    ///     preview of it (``previewNodes(for:)``); `nil` merges into the node as it stands.
    /// - Returns: The ref node with the override merged in.
    /// - Throws: What ``applyOverrideDescendant(_:)`` throws.
    func overriddenNode(for op: EditOperation.OverrideDescendant, onto base: PenNode? = nil) throws -> PenNode {
        var (node, refData) = try requireRef(op.refNodeID, onto: base)
        try validateOverrideTarget(op)
        try validateOverrideValues(op)
        try refuseComponentLoops(closedBy: .overrideDescendant(op))

        var descendants = refData.descendants ?? [:]
        let entry = descendants[op.descendantID]?.properties ?? [:]
        // A raw operation naming a Woodcase-owned key stores it in the entry's metadata,
        // as a planned one already does (rule 6).
        let write = NodePropertyCodec.foldingNaturalOverrideKeys(op.properties, unset: op.unset, onto: entry)
        let properties = Self.merging(write.properties, into: entry, removing: write.unset)
        // An entry with no keys left is not an override of nothing; it is no override,
        // and that is how it should read back.
        descendants[op.descendantID] = properties.isEmpty
            ? nil
            : PenDescendantOverride(properties: properties)
        refData.descendants = descendants.isEmpty ? nil : descendants

        node.kind = .ref(refData)
        return node
    }

    /// The ref node and its payload: `base` when given, which must be a ref, else the
    /// stored node.
    ///
    /// - Parameters:
    ///   - nodeID: The id of the ref node, which must be stored.
    ///   - base: A preview of the node to read in place of the stored one, or `nil`.
    /// - Returns: The node and the ref data it carries.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func requireRef(_ nodeID: String, onto base: PenNode?) throws -> (node: PenNode, data: PenNode.RefData) {
        let stored = try requireRef(nodeID)
        guard let base else { return stored }
        guard case let .ref(data) = base.kind else { throw EditingError.notARefNode(id: nodeID) }
        return (base, data)
    }

    /// Merges one override map into another, then drops the keys a write unsets.
    ///
    /// The order is what makes `key=value --unset key` meaningless rather than
    /// order-dependent: a caller who writes both is refused before reaching here.
    ///
    /// - Parameters:
    ///   - properties: The keys the write assigns.
    ///   - existing: The map as it stands.
    ///   - unset: The keys the write removes.
    /// - Returns: The map the write leaves behind.
    static func merging(
        _ properties: [String: AnyCodable],
        into existing: [String: AnyCodable],
        removing unset: [String]
    ) -> [String: AnyCodable] {
        var result = existing
        result.merge(properties) { _, new in new }
        for key in unset {
            result.removeValue(forKey: key)
        }
        return result
    }
}
