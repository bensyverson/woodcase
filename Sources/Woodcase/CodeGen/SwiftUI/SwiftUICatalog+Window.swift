//
//  SwiftUICatalog+Window.swift
//  Woodcase
//

extension SwiftUICatalog {
    /// `PenCatalog.swift`: the sheet in a scroll view of both axes, under the theme a
    /// picker per axis sets (no picker without axes). Its rows wrap at the window's width
    /// and it fills the window (`penCatalogViewport`); a specimen wider than the window
    /// keeps its size, and the window scrolls sideways to it.
    var catalogSource: String {
        let axes = theme?.axes ?? []
        var lines = Self.header("PenCatalog")
        lines += [
            "/// The catalog: every component in its states, every page, the theme's tokens and the",
            "/// document's type, in a scroll view\(axes.isEmpty ? "." : ", under the theme the toolbar's pickers set.")",
            "public struct PenCatalog: View {",
        ]
        if !axes.isEmpty {
            lines += ["    @State private var theme = PenTheme()", ""]
        }
        lines += [
            "    public init() {}",
            "",
            "    public var body: some View {",
            "        GeometryReader { window in",
            "            ScrollView([.horizontal, .vertical]) {",
            "                PenCatalogSheet()",
            "                    .penCatalogViewport(window.size)",
        ]
        if !axes.isEmpty {
            let arguments = axes.map { "\($0.property): theme.\($0.property)" }
            lines.append("                    .penTheme(\(arguments.joined(separator: ", ")))")
        }
        lines += ["            }", "        }"]
        if !axes.isEmpty {
            lines.append("        .toolbar {")
            for axis in axes {
                lines += [
                    "            Picker(\(SwiftUILiteral.string(axis.name)), selection: $theme.\(axis.property)) {",
                    "                ForEach(PenTheme.\(axis.typeName).allCases, id: \\.self) { option in",
                    "                    Text(option.rawValue).tag(option)",
                    "                }",
                    "            }",
                ]
            }
            lines.append("        }")
        }
        lines += ["    }", "}"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// `PenCatalogThemes.swift`: the sheet side by side under every theme variant — the
    /// default, then each axis's other options one at a time (``SwiftUITheme/variants``) —
    /// for a snapshot of the whole kit.
    var themesSource: String {
        let variants = theme?.variants ?? [SwiftUITheme.Variant(name: nil, modifier: nil)]
        var lines = Self.header("PenCatalogThemes")
        lines += [
            "/// The catalog's sheet side by side under every theme: the default, then each axis's other",
            "/// options one at a time. What `--snapshot` renders.",
            "public struct PenCatalogThemes: View {",
            "    public init() {}",
            "",
            "    public var body: some View {",
            "        HStack(alignment: .top, spacing: 0) {",
        ]
        for variant in variants {
            lines += [
                "            PenCatalogColumn(\(SwiftUILiteral.string(variant.name ?? "default"))) {",
                "                PenCatalogSheet()",
            ]
            if let modifier = variant.modifier {
                lines.append("                    \(modifier)")
            }
            lines.append("            }")
        }
        lines += ["        }", "    }", "}"]
        return lines.joined(separator: "\n") + "\n"
    }
}
