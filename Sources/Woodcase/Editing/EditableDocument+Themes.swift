//
//  EditableDocument+Themes.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Applies an ``EditOperation/AddThemeAxis`` operation.
    func applyAddThemeAxis(_ op: EditOperation.AddThemeAxis) throws {
        try requireNoThemeAxis(op.name)
        if themes == nil { themes = [:] }
        themes?[op.name] = op.options
        _layoutCache?.invalidateAll()
    }

    /// Applies an ``EditOperation/UpdateThemeAxis`` operation.
    func applyUpdateThemeAxis(_ op: EditOperation.UpdateThemeAxis) throws {
        try requireThemeAxis(op.name)
        themes?[op.name] = op.options
        _layoutCache?.invalidateAll()
    }

    /// Applies an ``EditOperation/RemoveThemeAxis`` operation.
    func applyRemoveThemeAxis(_ op: EditOperation.RemoveThemeAxis) throws {
        try requireThemeAxis(op.name)
        themes?[op.name] = nil
        if themes?.isEmpty == true { themes = nil }
        _layoutCache?.invalidateAll()
    }
}
