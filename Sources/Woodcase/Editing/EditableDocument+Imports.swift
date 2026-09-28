//
//  EditableDocument+Imports.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Applies an ``EditOperation/AddImport`` operation.
    func applyAddImport(_ op: EditOperation.AddImport) throws {
        try requireNoImport(op.alias)
        if imports == nil { imports = [:] }
        imports?[op.alias] = op.path
        _expansionCache?.invalidateAll()
        _layoutCache?.invalidateAll()
    }

    /// Applies an ``EditOperation/UpdateImport`` operation.
    func applyUpdateImport(_ op: EditOperation.UpdateImport) throws {
        try requireImport(op.alias)
        imports?[op.alias] = op.path
        _expansionCache?.invalidateAll()
        _layoutCache?.invalidateAll()
    }

    /// Applies an ``EditOperation/RemoveImport`` operation.
    func applyRemoveImport(_ op: EditOperation.RemoveImport) throws {
        try requireImport(op.alias)
        imports?[op.alias] = nil
        if imports?.isEmpty == true { imports = nil }
        _expansionCache?.invalidateAll()
        _layoutCache?.invalidateAll()
    }
}
