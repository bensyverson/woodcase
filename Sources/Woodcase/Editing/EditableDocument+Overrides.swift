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
        var (node, refData) = try requireRef(op.refNodeID)
        try validateOverrideTarget(op)
        try validateOverrideValues(op)

        var descendants = refData.descendants ?? [:]
        let properties = Self.merging(
            op.properties, into: descendants[op.descendantID]?.properties ?? [:], removing: op.unset
        )
        // An entry with no keys left is not an override of nothing; it is no override,
        // and that is how it should read back.
        descendants[op.descendantID] = properties.isEmpty
            ? nil
            : PenDescendantOverride(properties: properties)
        refData.descendants = descendants.isEmpty ? nil : descendants

        node.kind = .ref(refData)
        nodes[op.refNodeID] = node

        // Overrides can affect expanded size — invalidate layout for the ref node
        invalidateLayoutCache(for: op.refNodeID, category: .layout)
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
