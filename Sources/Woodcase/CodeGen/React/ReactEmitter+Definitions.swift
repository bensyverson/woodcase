//
//  ReactEmitter+Definitions.swift
//  Woodcase
//

extension ReactEmitter {
    /// Each tab bar's state variants, by variant id: the tab bar's name and the state the
    /// variant draws, so a ref to a variant is the tab bar with that state selected.
    static func variantStates(_ components: [ComponentDefinition]) -> [String: (componentName: String, stateName: String)] {
        var variantToState: [String: (componentName: String, stateName: String)] = [:]
        for component in components where component.role == .tabBar {
            for (stateName, variantID) in component.variantIDs {
                variantToState[variantID] = (componentName: component.name, stateName: stateName)
            }
        }
        return variantToState
    }

    /// One component's file, `components/<Name>.tsx`: the file the whole emit writes for it.
    ///
    /// `context` is where the emission accumulates, for the whole emit to read back what
    /// other files need.
    static func componentFile(
        _ component: ComponentDefinition,
        registry: [String: ComponentDefinition],
        variantToState: [String: (componentName: String, stateName: String)],
        theme: ThemeManifest,
        options: Options,
        diagnostics: PenDiagnosticCollector?,
        context: EmitContext = EmitContext()
    ) -> GeneratedFile {
        let content = emitComponent(
            component, theme: theme, registry: registry, variantToState: variantToState,
            options: options, diagnostics: diagnostics, context: context
        )
        return GeneratedFile(path: "components/\(component.name).tsx", content: content)
    }

    /// One page's file, `pages/<Name>.tsx`: the file the whole emit writes for it.
    ///
    /// `context` is where the emission accumulates, as for ``componentFile(_:registry:variantToState:theme:options:diagnostics:context:)``.
    static func pageFile(
        _ page: PageDefinition,
        registry: [String: ComponentDefinition],
        variantToState: [String: (componentName: String, stateName: String)],
        theme: ThemeManifest,
        options: Options,
        diagnostics: PenDiagnosticCollector?,
        context: EmitContext = EmitContext()
    ) -> GeneratedFile {
        let content = emitPage(
            page, registry: registry, variantToState: variantToState,
            theme: theme, options: options, diagnostics: diagnostics, context: context
        )
        return GeneratedFile(path: "pages/\(page.name).tsx", content: content)
    }

    /// The file of each definition in `selection`, in its order, with default options.
    static func code(
        for selection: DefinitionSelection,
        theme: ThemeManifest,
        diagnostics: PenDiagnosticCollector?
    ) -> [DefinitionCode] {
        let registry = Dictionary(selection.components.map { ($0.id, $0) }) { first, _ in first }
        let variantToState = variantStates(selection.components)
        let options = Options()
        return selection.entries.map { entry in
            switch entry {
            case let .component(component):
                DefinitionCode(
                    id: component.id, role: .component, typeName: component.name,
                    file: componentFile(
                        component, registry: registry, variantToState: variantToState,
                        theme: theme, options: options, diagnostics: diagnostics
                    )
                )
            case let .view(page):
                DefinitionCode(
                    id: page.id, role: .view, typeName: page.name,
                    file: pageFile(
                        page, registry: registry, variantToState: variantToState,
                        theme: theme, options: options, diagnostics: diagnostics
                    )
                )
            }
        }
    }
}
