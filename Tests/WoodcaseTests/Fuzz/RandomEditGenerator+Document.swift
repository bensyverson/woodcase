//
//  RandomEditGenerator+Document.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The CRDT set's document-level operations: variables, theme axes and imports, each
/// added when absent and updated or removed when present.
extension RandomEditGenerator {
    /// Adds, updates or removes one of five `fuzzVar` color variables.
    mutating func variableEdit(in doc: EditableDocument) -> EditOperation? {
        let varName = "fuzzVar\(Int.random(in: 0 ..< 5, using: &rng))"
        guard let existing = doc.variables?[varName] else {
            let variable = PenVariable(type: .color, value: .simple(AnyCodable(stringLiteral: hexColor())))
            return .addVariable(EditOperation.AddVariable(name: varName, variable: variable))
        }
        guard Bool.random(using: &rng) else {
            return .removeVariable(EditOperation.RemoveVariable(name: varName))
        }
        let variable = PenVariable(type: existing.type, value: .simple(AnyCodable(stringLiteral: hexColor())))
        return .updateVariable(EditOperation.UpdateVariable(name: varName, variable: variable))
    }

    /// Adds, updates or removes one of three `fuzzAxis` theme axes.
    mutating func themeAxisEdit(in doc: EditableDocument) -> EditOperation? {
        let axisName = "fuzzAxis\(Int.random(in: 0 ..< 3, using: &rng))"
        let options = Array(["optA", "optB", "optC"].prefix(Int.random(in: 2 ... 3, using: &rng)))
        guard doc.themes?[axisName] != nil else {
            return .addThemeAxis(EditOperation.AddThemeAxis(name: axisName, options: options))
        }
        guard Bool.random(using: &rng) else {
            return .removeThemeAxis(EditOperation.RemoveThemeAxis(name: axisName))
        }
        return .updateThemeAxis(EditOperation.UpdateThemeAxis(name: axisName, options: options))
    }

    /// Adds, updates or removes one of four `fuzzImport` aliases.
    mutating func importEdit(in doc: EditableDocument) -> EditOperation? {
        let alias = "fuzzImport\(Int.random(in: 0 ..< 4, using: &rng))"
        let path = "./fuzz\(Int.random(in: 0 ..< 10, using: &rng)).pen"
        guard doc.imports?[alias] != nil else {
            return .addImport(EditOperation.AddImport(alias: alias, path: path))
        }
        guard Bool.random(using: &rng) else {
            return .removeImport(EditOperation.RemoveImport(alias: alias))
        }
        return .updateImport(EditOperation.UpdateImport(alias: alias, path: path))
    }
}
