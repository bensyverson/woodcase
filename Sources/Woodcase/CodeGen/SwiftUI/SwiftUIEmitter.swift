//
//  SwiftUIEmitter.swift
//  Woodcase
//

import Foundation

/// Emits SwiftUI source from analyzed .pen components and pages, laid out as a SwiftPM package.
///
/// Every file is plain text: the emitter never imports SwiftUI, so it builds and its
/// goldens run wherever Foundation does. Layout is always idiomatic stacks — `HStack`,
/// `VStack`, `ZStack`, `Spacer`, `.frame`, `.padding` — chosen for intent over pixel
/// parity with Pen's flexbox; the few helpers the views need beyond SwiftUI itself (the
/// font with optical sizing pinned off, the line-height branch) are in the emitted
/// `Support/` files, `PenSupport.swift` and one `PenSupport+<Concern>.swift` per concern.
///
/// It writes frames, groups, rectangles, ellipses, arcs, polygons, paths, lines, icons and text
/// with their paints — colours, gradients, images, stacks, fill blend modes and opacity,
/// on shapes and on text — their strokes, and their effects, transforms and blend modes.
/// A path, polygon, line or arc is a `Shape` the file declares below its view.
/// A reusable component is a public view struct with a typed `let` per prop, and an
/// instance is a call to it, or — when a call cannot draw what Pen draws — the component
/// inlined with its overrides applied (``SwiftUINodeEmitter/instance(_:data:in:)``).
/// Every other node is a marked placeholder plus a warning.
///
/// The document's themes and variables are `Theme/PenTheme.swift`, a typed value the views
/// read from the environment (``SwiftUITheme``): a variable is `theme.<name>`, a node that
/// sets a theme sets it on its subtree with `penTheme(…)`, and a light/dark axis follows
/// SwiftUI's colour scheme.
///
/// Every component file ends with a `#Preview` per state a caller can pin, repeated under
/// each of the theme's other options; the package carries a catalog of the whole kit
/// (`Catalog/`) and a `<Module>Catalog` executable that opens it (`SwiftUICatalog`).
public enum SwiftUIEmitter {
    /// Emit a SwiftPM package for `components` and `pages`: `Package.swift`,
    /// `Sources/<module>/Components/<Component>.swift`, `Sources/<module>/Pages/<Page>.swift`,
    /// the theme under `Sources/<module>/Theme/` when the document has themes or variables,
    /// every template under `Sources/<module>/Support/`, the catalog under
    /// `Sources/<module>/Catalog/` and its executable, `Sources/<module>Catalog/main.swift`,
    /// and `Sources/<module>/Resources/`, which always exists (``resourcesPlaceholder(module:)``).
    ///
    /// - Parameters:
    ///   - document: The document the definitions came from, whose reusable nodes an
    ///     inlined instance is drawn from.
    ///   - components: The document's reusable components, one view struct each.
    ///   - pages: The pages to emit, one view struct each.
    ///   - theme: The document's themes and variables (``ThemeAnalyzer``), which the views
    ///     read through `PenTheme`.
    ///   - options: The floor and the module name.
    ///   - diagnostics: Receives a warning for every node or property written as a
    ///     placeholder or left out, and for every instance inlined.
    /// - Returns: The generated files, the local images the views paint with, the icon
    ///   libraries they draw from and the text font families they set. The caller copies
    ///   the images, the icon fonts (``iconFontFiles(for:)``) and the families' files
    ///   (``GoogleFontResolver/fontBundle(for:declaredIn:relativeTo:)``) into
    ///   `Sources/<module>/Resources/`; the views load them from `Bundle.module`, and the
    ///   support file registers every font there (`PenFonts`).
    /// - Throws: ``WoodcaseResources/Missing`` when the support templates cannot be read
    ///   because the resource bundle is not installed.
    public static func emit(
        document: PenDocument,
        components: [ComponentDefinition],
        pages: [PageDefinition],
        theme themeManifest: ThemeManifest,
        options: Options = Options(),
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> EmitResult {
        let templates = try supportTemplates()
        let typeNames = componentTypeNames(components)
        let theme = SwiftUITheme(themeManifest)
        for problem in theme?.problems ?? [] {
            diagnostics?.warn("SwiftUI's theme leaves out \(problem)", stage: .codeGen)
        }
        let scope = SwiftUIComponentScope(document: document, components: components, typeNames: typeNames, theme: theme)
        let root = "Sources/\(options.moduleName)"
        // What the views draw is the trees with every instance expanded: an override can
        // name an image the component never does.
        let drawn = (components.map(\.sourceNode) + pages.map(\.sourceNode)).map {
            PenRefExpander.expand($0, registry: scope.reusable)
        }
        let images = drawn.reduce(into: Set<String>()) { $0.formUnion(imageAssetURLs(in: $1)) }
        warnCollidingImages(images, diagnostics: diagnostics)
        let icons = drawn.reduce(into: Set<String>()) { $0.formUnion(iconLibraries(in: $1)) }
        let faces = drawn.reduce(into: Set<PenFontFace>()) { $0.formUnion(fontFaces(in: $1, theme: theme)) }
        var files: [GeneratedFile] = [manifest(options: options), resourcesPlaceholder(module: options.moduleName)]
        for definition in components {
            guard let component = scope.components[definition.id] else { continue }
            files.append(GeneratedFile(
                path: "\(root)/Components/\(component.typeName).swift",
                content: emitComponent(component, scope: scope, diagnostics: diagnostics)
            ))
        }
        let taken = Set(typeNames.values)
        let pageTypes = pages.map { (page: $0, type: typeName(for: $0, taken: taken)) }
        for (page, type) in pageTypes {
            files.append(GeneratedFile(
                path: "\(root)/Pages/\(type).swift",
                content: emitPage(page, named: type, scope: scope, diagnostics: diagnostics)
            ))
        }
        if let theme {
            files.append(GeneratedFile(path: "\(root)/Theme/PenTheme.swift", content: theme.themeSource))
            files.append(GeneratedFile(path: "\(root)/Theme/PenTheme+Environment.swift", content: theme.environmentSource))
        }
        for name in templates.keys.sorted() {
            files.append(GeneratedFile(path: "\(root)/Support/\(name)", content: templates[name] ?? ""))
        }
        let emitted = components.compactMap { scope.components[$0.id] }
        files += catalog(components: emitted, pages: pageTypes, drawn: drawn, theme: theme).files(module: options.moduleName)
        return EmitResult(files: files, iconLibraries: icons, imageAssetURLs: images, fontFaces: faces)
    }

    /// The source of one page: a public view struct named `type` whose body is the page's
    /// root frame.
    static func emitPage(
        _ page: PageDefinition, named type: String, scope: SwiftUIComponentScope, diagnostics: PenDiagnosticCollector?
    ) -> String {
        var emitter = SwiftUINodeEmitter(diagnostics: diagnostics)
        emitter.scope = scope
        let body = emitter.view(for: page.sourceNode, in: .root)
            ?? SwiftUIViewCode(head: "EmptyView()")
        let frameName = page.sourceNode.common.name ?? page.sourceNode.id
        var lines = header(type, source: "the \(SwiftUILiteral.string(frameName)) frame")
        lines += [
            "public struct \(type): View {",
            "    public init() {}",
            "",
        ]
        lines += bodyLines(body, emitter: emitter, preview: type)
        return lines.joined(separator: "\n") + "\n"
    }

    /// A file's opening comment, naming the file and what it was generated from, and its
    /// import.
    static func header(_ type: String, source: String) -> [String] {
        [
            "//",
            "//  \(type).swift",
            "//  Generated by Woodcase from \(source). Do not edit.",
            "//",
            "",
            "import SwiftUI",
            "",
        ]
    }

    /// A view struct's `body` and closing brace — after the environment's theme, when the
    /// body reads it outside every `PenThemeReader` — then `trailer`, the shapes its
    /// emitter declared, and the previews of `preview()`, one per theme variant
    /// (``previewLines(_:theme:)``).
    static func bodyLines(_ body: SwiftUIViewCode, emitter: SwiftUINodeEmitter, preview: String, trailer: [String] = []) -> [String] {
        var lines: [String] = []
        if emitter.themeReads.count > 0 {
            lines += ["    @Environment(\\.penTheme) private var theme", ""]
        }
        lines.append("    public var body: some View {")
        lines.append(contentsOf: body.lines(indent: 2))
        lines.append(contentsOf: [
            "    }",
            "}",
            "",
        ])
        lines += trailer
        for declaration in emitter.shapes.declarations {
            lines.append(contentsOf: declaration.lines + [""])
        }
        lines += previewLines([Specimen(name: nil, call: ["\(preview)()"])], theme: emitter.scope.theme)
        return lines
    }
}
