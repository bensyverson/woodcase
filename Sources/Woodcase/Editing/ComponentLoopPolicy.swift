//
//  ComponentLoopPolicy.swift
//  Woodcase
//

import Foundation

/// Whether ``EditableDocument/apply(_:)`` refuses an edit that would close a component
/// loop (``ComponentLoop``).
enum ComponentLoopPolicy: Friendly {
    /// Refuse it with ``EditingError/wouldCloseComponentLoop(path:)``: every edit a
    /// person or an agent makes.
    case refuse

    /// Let it through: replaying operations whose end state is already settled — an undo
    /// or a rollback returning to a state the document held, or a merge whose result was
    /// checked as a whole and whose steps may pass through a loop on the way.
    case allow
}
