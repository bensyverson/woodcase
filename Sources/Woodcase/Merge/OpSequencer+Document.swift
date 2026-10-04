//
//  OpSequencer+Document.swift
//  Woodcase
//

import Foundation

/// The document-level operations: entries and root properties first, removals and
/// table declarations last.
extension OpSequencer {
    /// Phase 1: adds or updates every import, theme axis and variable the merge takes
    /// from theirs, then sets the root properties it takes, in one patch.
    mutating func addDocumentEntries() {
        for key in sortedDocumentKeys() {
            switch key {
            case let .importAlias(alias):
                guard let path = theirs.imports?[alias] else { continue }
                operations.append(ours.imports?[alias] == nil
                    ? .addImport(EditOperation.AddImport(alias: alias, path: path))
                    : .updateImport(EditOperation.UpdateImport(alias: alias, path: path)))
            case let .themeAxis(axis):
                guard let options = theirs.themes?[axis] else { continue }
                operations.append(ours.themes?[axis] == nil
                    ? .addThemeAxis(EditOperation.AddThemeAxis(name: axis, options: options))
                    : .updateThemeAxis(EditOperation.UpdateThemeAxis(name: axis, options: options)))
            default:
                continue
            }
        }
        for case let .variable(name) in sortedDocumentKeys() {
            guard let variable = theirs.variables?[name] else { continue }
            operations.append(ours.variables?[name] == nil
                ? .addVariable(EditOperation.AddVariable(name: name, variable: variable))
                : .updateVariable(EditOperation.UpdateVariable(name: name, variable: variable)))
        }

        var properties: [String: AnyCodable] = [:]
        for key in resolution.document {
            guard let property = Self.propertyKey(of: key) else { continue }
            properties[property] = (try? DocumentPropertyCodec.value(at: property, of: theirs)) ?? .null
        }
        if !properties.isEmpty {
            operations.append(.setDocumentProperties(EditOperation.SetDocumentProperties(properties: properties)))
        }
    }

    /// Phase 7: removes every variable, import and theme axis theirs removed, then
    /// declares or leaves out each table so its declaration is the merged one.
    mutating func removeDocumentEntries() {
        for key in sortedDocumentKeys() {
            switch key {
            case let .variable(name) where theirs.variables?[name] == nil && ours.variables?[name] != nil:
                operations.append(.removeVariable(EditOperation.RemoveVariable(name: name)))
            case let .importAlias(alias) where theirs.imports?[alias] == nil && ours.imports?[alias] != nil:
                operations.append(.removeImport(EditOperation.RemoveImport(alias: alias)))
            case let .themeAxis(axis) where theirs.themes?[axis] == nil && ours.themes?[axis] != nil:
                operations.append(.removeThemeAxis(EditOperation.RemoveThemeAxis(name: axis)))
            default:
                continue
            }
        }

        var declarations: [String: AnyCodable] = [:]
        for table in DocumentChangeKey.Table.allCases {
            let (predicted, wanted) = declaration(of: table)
            if predicted != wanted {
                declarations[table.rawValue] = wanted ? .dictionary([:]) : .null
            }
        }
        if !declarations.isEmpty {
            operations.append(.setDocumentProperties(EditOperation.SetDocumentProperties(properties: declarations)))
        }
    }

    /// Whether a table is declared once the entry operations have run, and whether
    /// the merged document declares it.
    ///
    /// Removing a table's last entry leaves the table out, so a table emptied by the
    /// merge is predicted absent; one that keeps an entry is declared either way.
    private func declaration(of table: DocumentChangeKey.Table) -> (predicted: Bool, wanted: Bool) {
        let (oursKeys, theirsKeys) = entries(of: table)
        let touched = resolution.document.compactMap { key -> String? in
            switch (key, table) {
            case let (.variable(name), .variables), let (.importAlias(name), .imports), let (.themeAxis(name), .themes): name
            default: nil
            }
        }
        var merged = oursKeys ?? []
        var removedAny = false
        for name in touched {
            if theirsKeys?.contains(name) == true {
                merged.insert(name)
            } else if merged.remove(name) != nil {
                removedAny = true
            }
        }
        guard merged.isEmpty else { return (true, true) }
        let predicted = oursKeys != nil && !removedAny
        let wanted = resolution.document.contains(.declaredTable(table)) ? theirsKeys != nil : oursKeys != nil
        return (predicted, wanted)
    }

    /// A table's entry names on each side, `nil` where the side leaves the table out.
    private func entries(of table: DocumentChangeKey.Table) -> (ours: Set<String>?, theirs: Set<String>?) {
        switch table {
        case .variables: (ours.variables.map { Set($0.keys) }, theirs.variables.map { Set($0.keys) })
        case .imports: (ours.imports.map { Set($0.keys) }, theirs.imports.map { Set($0.keys) })
        case .themes: (ours.themes.map { Set($0.keys) }, theirs.themes.map { Set($0.keys) })
        }
    }

    /// The document keys the merge takes, in a stable order.
    private func sortedDocumentKeys() -> [DocumentChangeKey] {
        resolution.document.sorted { String(describing: $0) < String(describing: $1) }
    }

    /// The ``DocumentPropertyCodec`` key a document key is written through in phase 1,
    /// or `nil` for an entry key or a table's declaration.
    private static func propertyKey(of key: DocumentChangeKey) -> String? {
        switch key {
        case .fonts: DocumentPropertyCodec.fontsKey
        case .version: DocumentPropertyCodec.versionKey
        case .fileToken: DocumentPropertyCodec.fileTokenKey
        case let .extra(name): DocumentPropertyCodec.extrasPrefix + name
        case .variable, .importAlias, .themeAxis, .rootOrder, .declaredTable: nil
        }
    }
}
