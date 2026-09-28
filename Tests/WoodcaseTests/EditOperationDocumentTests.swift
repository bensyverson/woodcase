//
//  EditOperationDocumentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationDocumentTests {
    // MARK: - Variable Operations

    @Test("addVariable adds to variables dict")
    func addVariable() throws {
        let editable = EditableDocument(from: PenDocument(children: []))
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))

        try editable.apply(.addVariable(EditOperation.AddVariable(name: "primary", variable: variable)))

        #expect(editable.variables?["primary"]?.type == .color)
    }

    @Test("addVariable rejects duplicate name")
    func addVariableDuplicate() throws {
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))
        let doc = PenDocument(
            variables: ["primary": variable],
            children: []
        )
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.variableAlreadyExists(name: "primary")) {
            try editable.apply(.addVariable(EditOperation.AddVariable(name: "primary", variable: variable)))
        }
    }

    @Test("updateVariable modifies existing")
    func updateVariable() throws {
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))
        let doc = PenDocument(variables: ["primary": variable], children: [])
        let editable = EditableDocument(from: doc)

        let updated = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        try editable.apply(.updateVariable(EditOperation.UpdateVariable(name: "primary", variable: updated)))

        #expect(editable.variables?["primary"]?.value == .simple(AnyCodable("#00ff00")))
    }

    @Test("updateVariable rejects unknown name")
    func updateVariableUnknown() throws {
        let editable = EditableDocument(from: PenDocument(children: []))
        let variable = PenVariable(type: .number, value: .simple(AnyCodable(42)))

        #expect(throws: EditingError.variableNotFound(name: "missing")) {
            try editable.apply(.updateVariable(EditOperation.UpdateVariable(name: "missing", variable: variable)))
        }
    }

    @Test("removeVariable removes from dict")
    func removeVariable() throws {
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))
        let doc = PenDocument(variables: ["primary": variable], children: [])
        let editable = EditableDocument(from: doc)

        try editable.apply(.removeVariable(EditOperation.RemoveVariable(name: "primary")))

        // When last variable removed, dict becomes nil
        #expect(editable.variables == nil)
    }

    @Test("removeVariable rejects unknown name")
    func removeVariableUnknown() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        #expect(throws: EditingError.variableNotFound(name: "missing")) {
            try editable.apply(.removeVariable(EditOperation.RemoveVariable(name: "missing")))
        }
    }

    // MARK: - Import Operations

    @Test("addImport adds to imports dict")
    func addImport() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        try editable.apply(.addImport(EditOperation.AddImport(alias: "icons", path: "icons.pen")))

        #expect(editable.imports?["icons"] == "icons.pen")
    }

    @Test("addImport rejects duplicate alias")
    func addImportDuplicate() throws {
        let doc = PenDocument(imports: ["icons": "icons.pen"], children: [])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.importAlreadyExists(alias: "icons")) {
            try editable.apply(.addImport(EditOperation.AddImport(alias: "icons", path: "other.pen")))
        }
    }

    @Test("updateImport modifies existing path")
    func updateImport() throws {
        let doc = PenDocument(imports: ["icons": "icons.pen"], children: [])
        let editable = EditableDocument(from: doc)

        try editable.apply(.updateImport(EditOperation.UpdateImport(alias: "icons", path: "new-icons.pen")))

        #expect(editable.imports?["icons"] == "new-icons.pen")
    }

    @Test("updateImport rejects unknown alias")
    func updateImportUnknown() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        #expect(throws: EditingError.importNotFound(alias: "missing")) {
            try editable.apply(.updateImport(EditOperation.UpdateImport(alias: "missing", path: "x.pen")))
        }
    }

    @Test("removeImport removes from dict")
    func removeImport() throws {
        let doc = PenDocument(imports: ["icons": "icons.pen"], children: [])
        let editable = EditableDocument(from: doc)

        try editable.apply(.removeImport(EditOperation.RemoveImport(alias: "icons")))

        #expect(editable.imports == nil)
    }

    @Test("removeImport rejects unknown alias")
    func removeImportUnknown() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        #expect(throws: EditingError.importNotFound(alias: "missing")) {
            try editable.apply(.removeImport(EditOperation.RemoveImport(alias: "missing")))
        }
    }

    // MARK: - Theme Operations

    @Test("addThemeAxis adds axis with options")
    func addThemeAxis() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        try editable.apply(.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"])))

        #expect(editable.themes?["mode"] == ["light", "dark"])
    }

    @Test("addThemeAxis rejects duplicate name")
    func addThemeAxisDuplicate() throws {
        let doc = PenDocument(themes: ["mode": ["light", "dark"]], children: [])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.themeAxisAlreadyExists(name: "mode")) {
            try editable.apply(.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["a"])))
        }
    }

    @Test("updateThemeAxis modifies options")
    func updateThemeAxis() throws {
        let doc = PenDocument(themes: ["mode": ["light", "dark"]], children: [])
        let editable = EditableDocument(from: doc)

        try editable.apply(.updateThemeAxis(EditOperation.UpdateThemeAxis(name: "mode", options: ["light", "dark", "auto"])))

        #expect(editable.themes?["mode"] == ["light", "dark", "auto"])
    }

    @Test("updateThemeAxis rejects unknown name")
    func updateThemeAxisUnknown() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        #expect(throws: EditingError.themeAxisNotFound(name: "missing")) {
            try editable.apply(.updateThemeAxis(EditOperation.UpdateThemeAxis(name: "missing", options: ["a"])))
        }
    }

    @Test("removeThemeAxis removes from dict")
    func removeThemeAxis() throws {
        let doc = PenDocument(themes: ["mode": ["light", "dark"]], children: [])
        let editable = EditableDocument(from: doc)

        try editable.apply(.removeThemeAxis(EditOperation.RemoveThemeAxis(name: "mode")))

        #expect(editable.themes == nil)
    }

    @Test("removeThemeAxis rejects unknown name")
    func removeThemeAxisUnknown() throws {
        let editable = EditableDocument(from: PenDocument(children: []))

        #expect(throws: EditingError.themeAxisNotFound(name: "missing")) {
            try editable.apply(.removeThemeAxis(EditOperation.RemoveThemeAxis(name: "missing")))
        }
    }
}
