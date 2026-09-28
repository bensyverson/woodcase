//
//  EditableDocument+SlotFillRewrite.swift
//  Woodcase
//

import Foundation

/// Overrides addressed to content an instance wrote into its own slot, rewritten into the
/// slot fill that holds it.
///
/// Pen lets no key of an instance name content that instance wrote into a slot itself —
/// bare or by path, the key is dropped (`project/2026-09-26-slot-override-keys.md`,
/// rule 5). The content is still an address, and a write to it means one thing: change
/// that node. The node lives in the `children` value the instance wrote for the slot, so
/// that is where the write goes — one override of the slot's key carrying the whole list
/// with the node changed, which is what is recorded, replicated and undone.
extension EditableDocument {
    /// An override rewritten into the slot fill that holds its target.
    struct SlotFillRewrite: Friendly {
        /// The override that takes its place: the fill's `descendants` key, carrying the
        /// rewritten `children`.
        var operation: EditOperation.OverrideDescendant

        /// The full name path of the slot whose fill was rewritten — the one the
        /// instance's `descendants` map keys, even when the node sits deeper, inside a
        /// frame or an injected instance's own fill.
        var slotPath: String
    }

    /// The rewrite for an override on content the instance wrote into its own slot.
    ///
    /// The values are judged against the node itself first: folded into the slot's list,
    /// a value the node cannot take would be refused as a bad `children`, naming the
    /// wrong thing.
    ///
    /// - Parameter op: The override as addressed.
    /// - Returns: The rewrite, or `nil` when the key names no content the instance wrote
    ///   into a slot itself — the override stands as it is.
    /// - Throws: ``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``.
    func slotFillRewrite(of op: EditOperation.OverrideDescendant) throws -> SlotFillRewrite? {
        guard ownSlotContentKeys(ofInstance: op.refNodeID).contains(op.descendantID),
              case let .ref(refData) = nodes[op.refNodeID]?.kind,
              let descendants = refData.descendants
        else { return nil }
        try validateOverrideValues(op)

        let patch = SlotFillPatch(properties: op.properties, unset: op.unset)
        let steps = op.descendantID.split(separator: NodeAddress.separator).map(String.init)
        guard let rewritten = patch.rewrite(fills: descendants.mapValues(\.properties), steps: steps)
        else { return nil }
        return SlotFillRewrite(
            operation: EditOperation.OverrideDescendant(
                refNodeID: op.refNodeID,
                descendantID: rewritten.key,
                properties: [PenNodePatcher.childrenKey: .array(rewritten.children)]
            ),
            slotPath: namePath(ofDescendant: rewritten.key, in: op.refNodeID)
        )
    }
}
