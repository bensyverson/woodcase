//
//  MeshThemes.swift
//  Woodcase
//

/// Which themes a mesh gradient fill changes under, and the fill resolved under each.
///
/// Codegen keeps variables symbolic, but a mesh is not something any target can paint
/// from symbols alone: React bakes it to a raster, SwiftUI writes literal colors into a
/// `MeshGradient`. So the mesh is resolved once per theme it can depend on, and the
/// emitter switches between the results the way it switches a themed color.
enum MeshThemes {
    /// One theme a mesh is resolved under.
    struct Theme: Friendly {
        /// Every relevant axis's option: what the resolver is asked to apply.
        var selection: [String: String]

        /// The axes whose option differs from the default, which is what an emitter keys
        /// the theme's value on; empty for the default theme.
        var conditions: [String: String]
    }

    /// The themes a mesh must be resolved under: one per combination of the options of
    /// every axis its colors (or opacity) can depend on, through variable chains too. A
    /// mesh with no themed variable needs exactly one, the default.
    static func themes(for fill: PenFill.PenMeshGradientFill, in manifest: ThemeManifest) -> [Theme] {
        let axes = axes(for: fill, in: manifest)
        var selections: [[String: String]] = [[:]]
        for axis in axes {
            selections = selections.flatMap { selection in
                axis.values.map { option in selection.merging([axis.name: option]) { $1 } }
            }
        }
        return selections.map { selection in
            Theme(
                selection: selection,
                conditions: selection.filter { name, option in
                    axes.first { $0.name == name }?.values.first != option
                }
            )
        }
    }

    /// The fill with its variables resolved under `theme`, by the same resolver the
    /// renderer uses, over a document rebuilt from the manifest.
    static func resolvedFill(
        _ fill: PenFill.PenMeshGradientFill,
        theme: [String: String],
        in manifest: ThemeManifest
    ) -> PenFill.PenMeshGradientFill {
        let usesVariables = fill.colors?.contains { $0.variableName != nil } == true || fill.opacity?.variableName != nil
        guard usesVariables else { return fill }
        let document = PenDocument(
            themes: Dictionary(manifest.axes.map { ($0.name, $0.values) }) { first, _ in first },
            variables: Dictionary(manifest.variables.map { ($0.name, penVariable($0)) }) { first, _ in first },
            children: [PenNode(
                id: "mesh",
                common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData(fills: .single(.meshGradient(fill))))
            )]
        )
        let resolved = PenVariableResolver.resolve(document, theme: theme)
        guard case let .rectangle(data) = resolved.children.first?.kind,
              case let .meshGradient(resolvedFill)? = data.fills?.all.first
        else { return fill }
        return resolvedFill
    }

    /// The theme axes a mesh's variables reach, each with its options (default first).
    private static func axes(for fill: PenFill.PenMeshGradientFill, in manifest: ThemeManifest) -> [ThemeAxis] {
        var pending = (fill.colors ?? []).compactMap(\.variableName)
        if let opacity = fill.opacity?.variableName {
            pending.append(opacity)
        }
        var visited: Set<String> = []
        var axisNames: Set<String> = []
        while let name = pending.popLast() {
            guard visited.insert(name).inserted,
                  let variable = manifest.variables.first(where: { $0.name == name })
            else { continue }
            for value in variable.values {
                axisNames.formUnion(value.conditions.keys)
                if case let .string(text) = value.value, text.hasPrefix("$") {
                    pending.append(String(text.dropFirst()))
                }
            }
        }
        return manifest.axes.filter { axisNames.contains($0.name) && !$0.values.isEmpty }
    }

    /// The document variable a manifest entry was analyzed from. An unconditioned themed
    /// value is the document's `theme`-less default, which the resolver ranks below a
    /// matching condition.
    private static func penVariable(_ info: VariableInfo) -> PenVariable {
        guard info.isThemed else {
            return PenVariable(type: info.type, value: .simple(info.values.first?.value ?? .null))
        }
        return PenVariable(type: info.type, value: .themed(info.values.map { value in
            PenThemedValue(value: value.value, theme: value.conditions.isEmpty ? nil : value.conditions)
        }))
    }
}
