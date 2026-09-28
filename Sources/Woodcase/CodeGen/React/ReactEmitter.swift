//
//  ReactEmitter.swift
//  Woodcase
//

import Foundation

/// Accumulates state during component emission (icon imports, etc.).
final class EmitContext {
    var lines: [String] = []
    /// Icon import specifiers grouped by import path (e.g. `"lucide-react"` →
    /// `{"ArrowLeft", "Map as MapLucide"}`), written by ``iconLocalName(_:family:importPath:)``.
    var iconImports: [String: Set<String>] = [:]
    /// The icon each local icon name in the file stands for, keyed by that name.
    var iconBindings: [String: IconBinding] = [:]
    /// The name of the component or page the file declares.
    var ownName: String?
    /// Component references emitted as `<ComponentName />` tags that need imports.
    var componentRefs: Set<String> = []
    var componentRegistry: [String: ComponentDefinition] = [:]
    var options: ReactEmitter.Options = .init()
    var diagnostics: PenDiagnosticCollector?

    /// Maps variant node IDs to (base component name, state name) for tabBar ref resolution.
    var variantToState: [String: (componentName: String, stateName: String)] = [:]
    /// nodePath → {DeltaProperty} for designer-override states needing var() substitution.
    var stateAffectedProps: [String: Set<DeltaProperty>] = [:]
    /// The wc-* CSS class name, nil if component has no states.
    var stateClassName: String?
    /// Tracks the current node path during recursive emission (e.g. ".", "Background", "Header/Title").
    var currentNodePath: String = "."
    /// The document's theme manifest, which resolves a mesh fill's variables per theme.
    var theme = ThemeManifest(axes: [], variables: [], contextNodes: [])
    /// Per-theme mesh rasters the emitted styles reference by `var(--name)`, keyed by
    /// name; `theme.css` declares them.
    var meshProperties: [String: ThemedCustomProperty] = [:]
    /// How the container being emitted places its children: the container sets it around
    /// them — `free` when it places them by their own `x`/`y`.
    var childPlacement: ChildPlacement = .flow
    /// The fixed boxes the container being emitted gives its turned `fill_container`
    /// children and the fills sharing with them; ``ReactEmitter/emitNode(_:component:indent:ctx:isRoot:parentLayout:)``
    /// reads a child's before it emits it.
    var turnedFillSizes = TurnedFillSizes()
    /// The nodes already warned about for a shader fill React drops, so a node emitted twice
    /// in one file — a variant, an inlined instance — is named once.
    var shaderWarnedNodes: Set<String> = []
    /// The nodes already warned about for a blended shadow drawn unblended, likewise once.
    var unblendedShadowWarnedNodes: Set<String> = []
    /// The warnings already given, each once per node per file (``warnOnce(_:nodeID:)``).
    var issuedWarnings: Set<IssuedWarning> = []

    /// How the node with `common` is placed: free when it is absolutely positioned, else
    /// as its container places its children.
    func placement(for common: PenNodeCommon) -> ChildPlacement {
        common.layoutPosition == .absolute ? .free : childPlacement
    }

    /// The pivot the node with `common` turns about, which follows its ``placement(for:)``.
    func transformPivot(for common: PenNodeCommon) -> TransformPivot {
        placement(for: common).pivot
    }
}

/// Emits React + Tailwind `.tsx` component files from analyzed .pen components.
public enum ReactEmitter {
    /// Options controlling code-generation behavior.
    public struct Options: Friendly {
        /// When `true`, unmapped-override warnings become errors.
        public var strict: Bool

        /// Raster pixels per point for a baked mesh gradient whose box is fixed.
        ///
        /// The browser stretches the raster over the box, so a raster coarser than the
        /// display steps along a fold's or a transparent patch's edge. The default, 2,
        /// is a Retina display's density and the scale Pen's own PDF export embeds its
        /// meshes at; raise it for a denser display, lower it to shrink the emitted source.
        public var meshRasterScale: Double

        /// Creates options.
        ///
        /// - Parameters:
        ///   - strict: When `true`, unmapped-override warnings become errors.
        ///   - meshRasterScale: Raster pixels per point for a baked mesh gradient.
        public init(strict: Bool = false, meshRasterScale: Double = 2) {
            self.strict = strict
            self.meshRasterScale = meshRasterScale
        }
    }

    /// Emit `.tsx` files for each component definition.
    public static func emit(
        document _: PenDocument,
        components: [ComponentDefinition],
        theme: ThemeManifest,
        options: Options = Options(),
        diagnostics: PenDiagnosticCollector? = nil
    ) -> EmitResult {
        emit(
            document: PenDocument(version: "0", children: []),
            components: components,
            pages: [],
            theme: theme,
            options: options,
            diagnostics: diagnostics
        )
    }

    /// Emit `.tsx` files for components and pages.
    public static func emit(
        document _: PenDocument,
        components: [ComponentDefinition],
        pages: [PageDefinition],
        theme: ThemeManifest,
        options: Options = Options(),
        diagnostics: PenDiagnosticCollector? = nil
    ) -> EmitResult {
        let registry = Dictionary(
            uniqueKeysWithValues: components.map { ($0.id, $0) }
        )

        // Build variant-to-state lookup for tabBar ref resolution
        var variantToState: [String: (componentName: String, stateName: String)] = [:]
        for component in components where component.role == .tabBar {
            for (stateName, variantID) in component.variantIDs {
                variantToState[variantID] = (componentName: component.name, stateName: stateName)
            }
        }

        var files: [GeneratedFile] = []
        var meshProperties: [String: ThemedCustomProperty] = [:]

        // Component files
        for component in components {
            let ctx = EmitContext()
            let content = emitComponent(
                component, theme: theme, registry: registry,
                variantToState: variantToState,
                options: options, diagnostics: diagnostics, context: ctx
            )
            meshProperties.merge(ctx.meshProperties) { first, _ in first }
            files.append(GeneratedFile(
                path: "components/\(component.name).tsx",
                content: content
            ))
        }

        // Page files
        for page in pages {
            let ctx = EmitContext()
            let content = emitPage(
                page, registry: registry, variantToState: variantToState,
                theme: theme, options: options, diagnostics: diagnostics, context: ctx
            )
            meshProperties.merge(ctx.meshProperties) { first, _ in first }
            files.append(GeneratedFile(
                path: "pages/\(page.name).tsx",
                content: content
            ))
        }

        // Utility files
        files.append(emitCnUtility())
        files.append(emitThemeProvider(theme: theme))
        files.append(ThemeEmitter.emitCSS(
            theme: theme,
            customProperties: meshProperties.values.sorted { $0.name < $1.name }
        ))

        // States CSS (only if any components have states)
        let statesCSS = StateEmitter.emitCSS(for: components, diagnostics: diagnostics)
        if !statesCSS.isEmpty {
            files.append(GeneratedFile(path: "states.css", content: statesCSS))
        }

        // Manifest (for preview viewer and external tools)
        files.append(ManifestEmitter.emit(
            components: components, pages: pages, theme: theme
        ))

        // Collect icon libraries from the generated files by parsing import statements
        let iconLibraries = collectIconLibraries(from: files)

        // Collect image asset URLs from the generated file content
        let imageAssetURLs = collectImageURLs(from: files)

        return EmitResult(
            files: files,
            iconLibraries: iconLibraries,
            imageAssetURLs: imageAssetURLs
        )
    }

    // MARK: - Page Emission

    /// Emit one page's `.tsx`.
    ///
    /// A page declares no props of its own, but its root element goes through the same
    /// `isRoot` path a component root does — `className={cn("…", className)}` and a
    /// `...style` spread — so it takes the same two optional members from the same
    /// ``emitInterface(_:into:)``, over a props-less definition. They are defaulted
    /// (`= {}`) so a router can still render `<Home />` with no attributes at all.
    ///
    /// `ctx` is where the emission accumulates; pass one to read back what it collected
    /// for other files, such as per-theme mesh rasters for `theme.css`.
    static func emitPage(
        _ page: PageDefinition,
        registry: [String: ComponentDefinition],
        variantToState: [String: (componentName: String, stateName: String)] = [:],
        theme: ThemeManifest,
        options: Options = Options(),
        diagnostics: PenDiagnosticCollector? = nil,
        context ctx: EmitContext = EmitContext()
    ) -> String {
        ctx.theme = theme
        ctx.componentRegistry = registry
        ctx.variantToState = variantToState
        ctx.options = options
        ctx.diagnostics = diagnostics
        ctx.ownName = page.name

        // Interface (into separate lines first): className and style, nothing else
        let definition = dummyComponent(for: page)
        var interfaceLines: [String] = []
        emitInterface(definition, into: &interfaceLines)

        // Emit function body
        ctx.lines.append(
            "export function \(page.name)({ className, style }: \(page.name)Props = {}) {"
        )
        ctx.lines.append("  return (")
        emitNode(page.sourceNode, component: definition, indent: 4, ctx: ctx)
        ctx.lines.append("  );")
        ctx.lines.append("}")

        // Collect component imports by scanning for refs
        let refIDs = PageAnalyzer.referencedComponentIDs(in: page.sourceNode)
        var componentImports: [String] = []
        for refID in refIDs.sorted() {
            if let comp = registry[refID] {
                componentImports.append(
                    "import { \(comp.name) } from \"../components/\(comp.name)\";"
                )
            }
        }

        // Assemble with imports at top
        var lines: [String] = []
        for (importPath, names) in ctx.iconImports.sorted(by: { $0.key < $1.key }) {
            let sorted = names.sorted()
            lines.append("import { \(sorted.joined(separator: ", ")) } from \"\(importPath)\";")
        }
        lines.append("import { cn } from \"../lib/cn\";")
        for imp in componentImports.sorted() {
            lines.append(imp)
        }
        lines.append("")
        lines.append(contentsOf: interfaceLines)
        lines.append("")
        lines.append(contentsOf: ctx.lines)

        return lines.joined(separator: "\n") + "\n"
    }

    /// Create a minimal ComponentDefinition for page emission (pages have no props).
    static func dummyComponent(for page: PageDefinition) -> ComponentDefinition {
        ComponentDefinition(
            id: page.id,
            name: page.name,
            sourceNode: page.sourceNode,
            props: [],
            actions: [],
            bindings: []
        )
    }

    // MARK: - Component Emission

    /// Emit one component's `.tsx`.
    ///
    /// `ctx` is where the emission accumulates; pass one to read back what it collected
    /// for other files, such as per-theme mesh rasters for `theme.css`.
    static func emitComponent(
        _ component: ComponentDefinition,
        theme: ThemeManifest,
        registry: [String: ComponentDefinition] = [:],
        variantToState: [String: (componentName: String, stateName: String)] = [:],
        options: Options = Options(),
        diagnostics: PenDiagnosticCollector? = nil,
        context ctx: EmitContext = EmitContext()
    ) -> String {
        ctx.theme = theme
        ctx.componentRegistry = registry
        ctx.variantToState = variantToState
        ctx.options = options
        ctx.diagnostics = diagnostics
        ctx.ownName = component.name

        // Populate state context before emission
        let affected = StateEmitter.stateAffectedProperties(for: component)
        if !affected.isEmpty {
            ctx.stateAffectedProps = affected
        }
        // Set wc-* class whenever any states exist (smart defaults also need it)
        if !component.states.isEmpty {
            ctx.stateClassName = StateEmitter.cssClassName(for: component.name)
        }

        // Interface (into separate lines first)
        var interfaceLines: [String] = []
        emitInterface(component, into: &interfaceLines)

        // Function body (may accumulate icon imports)
        emitFunction(component, theme: theme, ctx: ctx)

        // Assemble final output with imports at top
        var lines: [String] = []
        for (importPath, names) in ctx.iconImports.sorted(by: { $0.key < $1.key }) {
            let sorted = names.sorted()
            lines.append("import { \(sorted.joined(separator: ", ")) } from \"\(importPath)\";")
        }
        lines.append("import { cn } from \"../lib/cn\";")
        // Import sibling components referenced via refs
        for name in ctx.componentRefs.sorted() where name != component.name {
            lines.append("import { \(name) } from \"./\(name)\";")
        }
        lines.append("")
        lines.append(contentsOf: interfaceLines)
        lines.append("")
        lines.append(contentsOf: ctx.lines)

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Icon Library Collection

    /// Scans generated file import statements to determine which icon libraries are used.
    private static func collectIconLibraries(from files: [GeneratedFile]) -> Set<String> {
        var libraries: Set<String> = []
        let pattern = /import\s*\{[^}]+\}\s*from\s*"([^"]+)"/
        for file in files where file.path.hasSuffix(".tsx") {
            for match in file.content.matches(of: pattern) {
                let importPath = String(match.output.1)
                if let family = IconLibraryMapping.family(forImportPath: importPath) {
                    libraries.insert(family)
                }
            }
        }
        return libraries
    }
}
