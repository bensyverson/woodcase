//
//  EditableDocument+Variables.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Applies an ``EditOperation/AddVariable`` operation.
    func applyAddVariable(_ op: EditOperation.AddVariable) throws {
        try requireNoVariable(op.name)
        if variables == nil { variables = [:] }
        variables?[op.name] = op.variable
        _layoutCache?.invalidateAll()
    }

    /// Applies an ``EditOperation/UpdateVariable`` operation.
    func applyUpdateVariable(_ op: EditOperation.UpdateVariable) throws {
        try requireVariable(op.name)
        variables?[op.name] = op.variable
        _layoutCache?.invalidateAll()
    }

    /// Applies an ``EditOperation/RemoveVariable`` operation.
    func applyRemoveVariable(_ op: EditOperation.RemoveVariable) throws {
        try requireVariable(op.name)
        variables?[op.name] = nil
        if variables?.isEmpty == true { variables = nil }
        _layoutCache?.invalidateAll()
    }
}
