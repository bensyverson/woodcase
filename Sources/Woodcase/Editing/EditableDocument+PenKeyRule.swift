//
//  EditableDocument+PenKeyRule.swift
//  Woodcase
//

import Foundation

/// The override-target guard's second opinion: Pen's own rule for which node a
/// `descendants` key names.
extension EditableDocument {
    /// Whether Pen's key rule places an override the key list does not hold.
    ///
    /// ``overridableDescendantKeys(ofInstance:)`` lists one key per node — the path
    /// ``PenRefExpander`` gives it. Pen also accepts other spellings for some of them:
    /// a bare id for a node the component wrote into a nested instance's slot, a path
    /// that steps through a frame or skips an instance. ``PenRefExpander`` applies
    /// those through ``PenOverrideKeyResolver``, so the guard asks the same resolver
    /// rather than a list of its own.
    ///
    /// - Parameter op: The override about to be applied.
    /// - Returns: `true` when the resolver places the key.
    func resolvesAsPen(_ op: EditOperation.OverrideDescendant) -> Bool {
        guard let componentID = componentRoot(ofInstanceChain: [op.refNodeID]) else { return false }
        let registry = materializedComponents()
        guard let component = registry[componentID] else { return false }
        return PenOverrideKeyResolver(component: component, registry: registry)
            .target(of: op.descendantID) != nil
    }
}
