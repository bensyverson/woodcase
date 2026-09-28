//
//  DocumentMutation.swift
//  Woodcase
//

import Foundation

/// An atomic mutation to apply to ``EditableDocument``'s flat store.
///
/// ``CRDTDocument/processRemote(operation:document:)`` returns an array of
/// these mutations, which the ``EditableDocument`` applies to update its
/// observable state.
public enum DocumentMutation: Friendly {
    /// Set or replace a node in the flat store.
    case setNode(PenNode)
    /// Remove a node from the flat store.
    case removeNode(nodeID: String)
    /// Set the children list for a parent (or root).
    case setChildren(parentID: String?, childIDs: [String])
    /// Set the parent of a node.
    case setParent(nodeID: String, parentID: String?)
    /// Remove the parent entry for a node.
    case removeParent(nodeID: String)
    /// Set a variable.
    case setVariable(name: String, variable: PenVariable)
    /// Remove a variable.
    case removeVariable(name: String)
    /// Set an import.
    case setImport(alias: String, path: String)
    /// Remove an import.
    case removeImport(alias: String)
    /// Set a theme axis.
    case setThemeAxis(name: String, options: [String])
    /// Remove a theme axis.
    case removeThemeAxis(name: String)
}
