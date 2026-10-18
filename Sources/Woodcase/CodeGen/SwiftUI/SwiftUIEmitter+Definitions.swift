//
//  SwiftUIEmitter+Definitions.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// One component's file, `<root>/Components/<Type>.swift`: the file the whole emit
    /// writes for it.
    static func componentFile(
        _ component: SwiftUIComponent, root: String, scope: SwiftUIComponentScope, diagnostics: PenDiagnosticCollector?
    ) -> GeneratedFile {
        GeneratedFile(
            path: "\(root)/Components/\(component.typeName).swift",
            content: emitComponent(component, scope: scope, diagnostics: diagnostics)
        )
    }

    /// One page's file, `<root>/Pages/<type>.swift`: the file the whole emit writes for it.
    static func pageFile(
        _ page: PageDefinition, named type: String, root: String, scope: SwiftUIComponentScope, diagnostics: PenDiagnosticCollector?
    ) -> GeneratedFile {
        GeneratedFile(
            path: "\(root)/Pages/\(type).swift",
            content: emitPage(page, named: type, scope: scope, diagnostics: diagnostics)
        )
    }

    /// The file of each definition in `selection`, in its order, with default options:
    /// each written as ``emit(document:components:pages:theme:options:diagnostics:)``
    /// writes it, against every component of `document`.
    ///
    /// - Throws: ``WoodcaseResources/Missing`` when the support templates cannot be read,
    ///   as the whole emit does: the names a view may not take depend on them.
    static func code(
        for selection: DefinitionSelection,
        in document: PenDocument,
        theme themeManifest: ThemeManifest,
        diagnostics: PenDiagnosticCollector?
    ) throws -> [DefinitionCode] {
        _ = try supportTemplates()
        let typeNames = componentTypeNames(selection.components)
        let theme = SwiftUITheme(themeManifest)
        let scope = SwiftUIComponentScope(document: document, components: selection.components, typeNames: typeNames, theme: theme)
        let root = "Sources/\(Options().moduleName)"
        let taken = Set(typeNames.values)
        return selection.entries.compactMap { entry in
            switch entry {
            case let .component(definition):
                guard let component = scope.components[definition.id] else { return nil }
                return DefinitionCode(
                    id: definition.id, role: .component, typeName: component.typeName,
                    file: componentFile(component, root: root, scope: scope, diagnostics: diagnostics)
                )
            case let .view(page):
                let type = typeName(for: page, taken: taken)
                return DefinitionCode(
                    id: page.id, role: .view, typeName: type,
                    file: pageFile(page, named: type, root: root, scope: scope, diagnostics: diagnostics)
                )
            }
        }
    }
}
