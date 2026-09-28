//
//  SwiftUICatalog.swift
//  Woodcase
//

/// The catalog the SwiftUI package carries, the counterpart of React's kit page
/// (``ViewerScaffolder``): `Catalog/PenCatalogSheet.swift`, every component in each state a
/// caller can pin, every page, the theme's tokens and the document's type;
/// `Catalog/PenCatalog.swift`, the sheet in a scroll view under a picker per theme axis;
/// `Catalog/PenCatalogThemes.swift`, the sheet side by side under every theme variant; and
/// the `<Module>Catalog` executable's `main.swift`, which opens the catalog in a window.
///
/// The sheet's pieces — sections, entries, specimens, swatches — are the support file
/// `PenSupport+Catalog.swift`.
struct SwiftUICatalog: Friendly {
    /// One component or page as the sheet shows it.
    struct Entry: Friendly {
        /// The heading: the name in the .pen file.
        var title: String

        /// The component's states, or the page's one bare call.
        var specimens: [SwiftUIEmitter.Specimen]
    }

    /// The components, in the document's order.
    var components: [Entry]

    /// The pages, in the document's order.
    var pages: [Entry]

    /// The document's theme, or `nil` when it has neither axes nor variables.
    var theme: SwiftUITheme?

    /// Every text style the components and pages set, largest first.
    var textStyles: [SwiftUICatalogTextStyle]

    /// The files the catalog adds to a package whose library is `module`: three under
    /// `Sources/<module>/Catalog/` and the executable's `Sources/<module>Catalog/main.swift`.
    func files(module: String) -> [GeneratedFile] {
        [
            GeneratedFile(path: "Sources/\(module)/Catalog/PenCatalog.swift", content: catalogSource),
            GeneratedFile(path: "Sources/\(module)/Catalog/PenCatalogSheet.swift", content: sheetSource),
            GeneratedFile(path: "Sources/\(module)/Catalog/PenCatalogThemes.swift", content: themesSource),
            GeneratedFile(path: "Sources/\(module)Catalog/main.swift", content: mainSource(module: module)),
        ]
    }

    /// The type names the catalog declares in the module, which no component or page may
    /// take.
    static let typeNames: Set<String> = ["PenCatalog", "PenCatalogSheet", "PenCatalogThemes"]

    /// A file's opening comment and import.
    static func header(_ name: String) -> [String] {
        SwiftUIEmitter.header(name, source: "the document's components, pages and theme")
    }

    /// `PenCatalogSheet.swift`: every component in its states, every page, and — when the
    /// document has a theme — its tokens and every text style, all under the environment's
    /// theme.
    var sheetSource: String {
        var lines = Self.header("PenCatalogSheet")
        lines += [
            "/// Every component in each state a caller can pin, every page, the theme's tokens and the",
            "/// document's type, drawn under the theme of the environment.",
            "public struct PenCatalogSheet: View {",
        ]
        if theme != nil {
            lines += ["    @Environment(\\.penTheme) private var theme", ""]
        }
        lines += [
            "    public init() {}",
            "",
            "    public var body: some View {",
            "        VStack(alignment: .leading, spacing: 48) {",
        ]
        if !components.isEmpty {
            lines += section("Components", components.flatMap(componentLines))
        }
        if !pages.isEmpty {
            lines += section("Pages", pages.flatMap(pageLines))
        }
        lines += tokenLines
        if !textStyles.isEmpty {
            lines += section("Type", flow(textStyles.flatMap(styleLines)))
        }
        lines += [
            "        }",
            "        .penCatalogPage()",
            "    }",
            "}",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// A section of the sheet's stack titled `title`, holding `content` (lines indented
    /// as the section's own).
    private func section(_ title: String, _ content: [String]) -> [String] {
        ["            PenCatalogSection(\(SwiftUILiteral.string(title))) {"]
            + content.map { "    " + $0 }
            + ["            }"]
    }

    /// `content` wrapped in a flow, for a section's run of swatches or specimens.
    private func flow(_ content: [String]) -> [String] {
        ["            PenCatalogFlow {"] + content.map { "    " + $0 } + ["            }"]
    }

    /// A component's entry: a specimen per state.
    private func componentLines(_ entry: Entry) -> [String] {
        var lines = ["            PenCatalogEntry(\(SwiftUILiteral.string(entry.title))) {"]
        for specimen in entry.specimens {
            lines.append("                PenCatalogSpecimen(\(SwiftUILiteral.string(specimen.name ?? "default"))) {")
            lines += specimen.call.map { "                    " + $0 }
            lines.append("                }")
        }
        lines.append("            }")
        return lines
    }

    /// A page's entry: the page, bare.
    private func pageLines(_ entry: Entry) -> [String] {
        ["            PenCatalogEntry(\(SwiftUILiteral.string(entry.title))) {"]
            + entry.specimens.flatMap { $0.call.map { "                " + $0 } }
            + ["            }"]
    }

    /// The colour section, a swatch per colour token, and the token section, a value per
    /// other token; none without a theme.
    private var tokenLines: [String] {
        let tokens = theme?.sortedTokens ?? []
        let colors = tokens.filter { $0.type == .color }
        let others = tokens.filter { $0.type != .color }
        var lines: [String] = []
        if !colors.isEmpty {
            lines += section("Colours", flow(colors.map {
                "                PenCatalogSwatch(\(SwiftUILiteral.string("$" + $0.variable)), color: \($0.read))"
            }))
        }
        if !others.isEmpty {
            lines += section("Tokens", flow(others.map {
                "                PenCatalogValue(\(SwiftUILiteral.string("$" + $0.variable)), value: \(Self.valueText($0)))"
            }))
        }
        return lines
    }

    /// The expression that shows a token's value as text.
    private static func valueText(_ token: SwiftUITheme.Token) -> String {
        switch token.type {
        case .number: "Double(\(token.read)).formatted()"
        case .string: token.read
        case .boolean, .color: "String(describing: \(token.read))"
        }
    }

    /// A text style's specimen: a line set in it over its caption.
    private func styleLines(_ style: SwiftUICatalogTextStyle) -> [String] {
        [
            "                PenCatalogSpecimen(\(SwiftUILiteral.string(style.label))) {",
            "                    Text(\(SwiftUILiteral.string(Self.pangram)))",
            "                        \(style.fontModifier)",
            "                }",
        ]
    }

    /// The line each text style is set in.
    static let pangram = "The quick brown fox jumps over the lazy dog"
}
