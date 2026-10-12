//
//  EditableDocument+BindableVariables.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The variables that may bind to a property of a node — what an inspector offers in
    /// its variable picker.
    ///
    /// Only variables of the type the property's ``PenPropertyShape/variable`` names are
    /// listed, from the document and from the libraries read with it (``PenReadContext``),
    /// so each one plans as ``EditIntent/bind(property:variable:)`` without a
    /// ``EditRefusal/Code/variableTypeMismatch``. Each carries its value under the theme
    /// the node draws with — the first option of every axis, overlaid by each
    /// `common.theme` from the root down to the node, through the instance for a node
    /// inside one — the same value ``EditIntent/unbind(property:)`` would write.
    ///
    /// ```swift
    /// document.bindableVariables(for: "kind.fills", at: address).map(\.name)  // ["brand", "ink"]
    /// ```
    ///
    /// - Parameters:
    ///   - property: A property path (`kind.fills`) or a raw key (`fill`).
    ///   - target: The node, as ``resolve(expandedID:)`` or ``resolve(_:tags:)-(String,_)``
    ///     returned it.
    /// - Returns: The variables, sorted by name; empty when the property takes no variable.
    func bindableVariables(for property: String, at target: ResolvedNodeAddress) -> [BindableVariable] {
        guard let type = NodePropertyCodec.bindableVariableType(of: property) else { return [] }
        let own = variables ?? [:]
        let candidates = own.merging(importedVariables) { mine, _ in mine }.filter { $0.value.type == type }
        guard !candidates.isEmpty else { return [] }
        let values = resolvedVariables(under: theme(of: target))
        return candidates.keys.sorted().map { name in
            BindableVariable(
                name: name,
                type: type,
                origin: own[name] != nil ? .document : .library(alias: Self.importAlias(of: name)),
                value: values[name]
            )
        }
    }
}

extension EditableDocument {
    /// Every variable's value under a theme, the document's own winning over an
    /// imported one of the same name, and aliases followed.
    ///
    /// - Parameter theme: Axis → option.
    /// - Returns: Name → value.
    func resolvedVariables(under theme: [String: String]) -> [String: AnyCodable] {
        PenVariableResolver.buildTable(
            from: (variables ?? [:]).merging(importedVariables) { own, _ in own },
            theme: theme,
            overrides: [:]
        )
    }

    /// The theme a node draws under, or the first option of each axis when the
    /// document cannot place it.
    private func theme(of target: ResolvedNodeAddress) -> [String: String] {
        let placed: EditPlanner.PlacedNode? = switch target {
        case let .node(id): EditPlanner.PlacedNode(node: id, in: self)
        case let .instanceDescendant(refID, key): EditPlanner.PlacedNode(descendant: key, ofInstance: refID, in: self)
        }
        if let placed { return placed.theme(axes: themes) }
        return (themes ?? [:]).compactMapValues(\.first)
    }

    /// The import alias an imported variable's name starts with — `K` in `K:accent`.
    private static func importAlias(of name: String) -> String {
        String(name.prefix { $0 != importSeparator })
    }
}
