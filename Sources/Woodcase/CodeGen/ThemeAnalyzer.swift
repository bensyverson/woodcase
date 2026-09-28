//
//  ThemeAnalyzer.swift
//  Woodcase
//

/// Analyzes a .pen document's theming information for code generation.
///
/// Extracts theme axes, variable definitions with their themed values,
/// and nodes with theme context overrides.
public enum ThemeAnalyzer {
    /// Analyze a document and produce a ``ThemeManifest``.
    public static func analyze(_ document: PenDocument) -> ThemeManifest {
        let axes = buildAxes(from: document)
        let variables = buildVariables(from: document)
        var contextNodes: [String] = []
        collectContextNodes(from: document.children, into: &contextNodes)
        return ThemeManifest(axes: axes, variables: variables, contextNodes: contextNodes)
    }

    // MARK: - Private

    private static func buildAxes(from document: PenDocument) -> [ThemeAxis] {
        guard let themes = document.themes else { return [] }
        return themes.map { ThemeAxis(name: $0.key, values: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private static func buildVariables(from document: PenDocument) -> [VariableInfo] {
        guard let variables = document.variables else { return [] }
        return variables.map { name, variable in
            let (isThemed, values) = extractValues(from: variable.value)
            return VariableInfo(
                name: name,
                type: variable.type,
                isThemed: isThemed,
                values: values
            )
        }.sorted { $0.name < $1.name }
    }

    private static func extractValues(
        from value: PenVariableValue
    ) -> (isThemed: Bool, values: [ThemedVariableValue]) {
        switch value {
        case let .simple(anyValue):
            return (false, [ThemedVariableValue(value: anyValue, conditions: [:])])
        case let .themed(themedValues):
            let mapped: [ThemedVariableValue] = themedValues.map { tv in
                ThemedVariableValue(value: tv.value, conditions: tv.theme ?? [:])
            }
            return (true, mapped)
        }
    }

    private static func collectContextNodes(from nodes: [PenNode], into result: inout [String]) {
        for node in nodes {
            if node.common.theme != nil {
                result.append(node.id)
            }
            for child in children(of: node) {
                collectContextNodes(from: [child], into: &result)
            }
        }
    }

    private static func children(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }
}
