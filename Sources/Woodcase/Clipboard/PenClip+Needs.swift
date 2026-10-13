//
//  PenClip+Needs.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// The variables and theme axes a clip's roots need.
    struct Needs: Friendly {
        /// The variables the roots use and the variables those reference, by name.
        var variables: [String: PenVariable]

        /// The axes those variables are themed on and the roots pin, each with every
        /// option it has.
        var themes: [String: [String]]
    }

    /// Works out the variables and theme axes a clip's roots need.
    ///
    /// A variable is used wherever a string leaf of a root's JSON is `$name` — the rule
    /// ``EditableDocument/variableReferences()`` reads by — and the closure follows each
    /// variable's own value, themed or not, to the variables it references. An axis is
    /// needed when a needed variable has a value for one of its options, or when a node
    /// or an override pins it with `theme`. The document's own definitions win over an
    /// imported one of the same name, as they do when the document resolves; an imported
    /// one keeps its prefixed name (`K:accent`), which is how the carried definitions
    /// already spell it.
    ///
    /// - Parameters:
    ///   - roots: The clip's roots: the copies and the carried definitions.
    ///   - document: The source document.
    /// - Returns: What the roots need; empty maps when they need nothing.
    static func needs(of roots: [PenNode], in document: EditableDocument) -> Needs {
        let imported = document.importedDefinitions
        let defined = (document.variables ?? [:]).merging(imported.variables) { own, _ in own }
        let axes = (document.themes ?? [:]).merging(imported.themes) { own, _ in own }

        var mentioned: Set<String> = []
        var pinned: Set<String> = []
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for root in roots {
            guard let data = try? encoder.encode(root),
                  let json = try? decoder.decode(AnyCodable.self, from: data)
            else { continue }
            scan(json, variables: &mentioned, axes: &pinned)
        }

        var needed: [String: PenVariable] = [:]
        var pending = Array(mentioned)
        while let name = pending.popLast() {
            guard needed[name] == nil, let variable = defined[name] else { continue }
            needed[name] = variable
            var referenced: Set<String> = []
            switch variable.value {
            case let .simple(value):
                EditableDocument.collectReferences(in: value, into: &referenced)
            case let .themed(variants):
                for variant in variants {
                    EditableDocument.collectReferences(in: variant.value, into: &referenced)
                    if let theme = variant.theme {
                        pinned.formUnion(theme.keys)
                    }
                }
            }
            pending += referenced
        }
        return Needs(variables: needed, themes: axes.filter { pinned.contains($0.key) })
    }

    /// Collects the variable names and theme axes a JSON value mentions.
    ///
    /// - Parameters:
    ///   - value: The value to walk.
    ///   - variables: The `$name` leaves found so far, without the `$`.
    ///   - axes: The keys of every `theme` object found so far.
    private static func scan(_ value: AnyCodable, variables: inout Set<String>, axes: inout Set<String>) {
        var pending = [value]
        while let current = pending.popLast() {
            switch current {
            case .string:
                EditableDocument.collectReferences(in: current, into: &variables)
            case let .array(items):
                pending += items
            case let .dictionary(entries):
                if case let .dictionary(pins)? = entries[themeKey] {
                    axes.formUnion(pins.keys)
                }
                pending += entries.values
            case .null, .bool, .int, .double:
                break
            }
        }
    }

    /// The key a node or an override pins theme options under.
    private static let themeKey = "theme"
}
