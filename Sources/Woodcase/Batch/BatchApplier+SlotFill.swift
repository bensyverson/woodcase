//
//  BatchApplier+SlotFill.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// The note an `override` line reports when its write was rewritten into a slot fill.
    ///
    /// The line still answers with the instance, as every `override` does; this is what
    /// says the typed address and the place written differ, and names both. It is a
    /// ``WriteDivergence/Severity/note``: the write means exactly what it looks like —
    /// the node changes — and where it is stored is the one fact worth stating.
    ///
    /// - Parameters:
    ///   - override: The override as addressed.
    ///   - rewrite: Where ``EditableDocument/slotFillRewrite(of:)`` put it.
    /// - Returns: The note, its ``WriteDivergence/requested`` the id address of the node
    ///   and its ``WriteDivergence/applied`` the slot's name path.
    static func slotFillNote(
        _ override: EditOperation.OverrideDescendant,
        landingIn rewrite: EditableDocument.SlotFillRewrite
    ) -> WriteDivergence {
        let address = "\(override.refNodeID)\(NodeAddress.separator)\(override.descendantID)"
        return WriteDivergence(
            kind: .slotFillRewrite,
            severity: .note,
            target: address,
            requested: address,
            applied: rewrite.slotPath,
            note: "\(address) is content this instance wrote into the slot \(rewrite.slotPath) itself, "
                + "so the change was written there, on the node in the slot's children — Pen ignores "
                + "an override an instance keys to its own slot content"
        )
    }
}
