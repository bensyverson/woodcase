//
//  SwiftUITheme+Environment.swift
//  Woodcase
//

extension SwiftUITheme {
    /// `PenTheme+Environment.swift`: the theme as an environment value, the `penTheme(…)`
    /// modifier a context node writes, and `PenThemeReader`, which hands a subtree the theme
    /// its context node set.
    ///
    /// When an axis's options are light and dark it *is* the colour scheme: the environment
    /// reads it from `colorScheme` and writing it sets `colorScheme`, so an app in dark mode
    /// draws the dark theme, and a subtree set dark draws SwiftUI's own controls dark too.
    var environmentSource: String {
        var lines = Self.header("PenTheme+Environment", source: "the document's themes")
        if let axis = bridgedAxis {
            lines += bridgedEnvironment(axis)
        } else {
            lines += [
                "public extension EnvironmentValues {",
                "    /// The theme views draw with.",
                "    var penTheme: PenTheme {",
                "        get { penThemeAxes }",
                "        set { penThemeAxes = newValue }",
                "    }",
                "}",
                "",
                "extension EnvironmentValues {",
                "    /// The theme as last set.",
                "    @Entry var penThemeAxes = PenTheme()",
                "}",
            ]
        }
        if !axes.isEmpty {
            let parameters = axes.map { "\($0.property): PenTheme.\($0.typeName)? = nil" }
            lines += [
                "",
                "public extension View {",
                "    /// This view with the theme set on the axes named, as a .pen node's `theme` sets it for",
                "    /// the node and everything under it; an axis left `nil` keeps the theme around the view.",
                "    func penTheme(\(parameters.joined(separator: ", "))) -> some View {",
                "        transformEnvironment(\\.penTheme) { theme in",
            ]
            lines += axes.map { "            if let \($0.property) { theme.\($0.property) = \($0.property) }" }
            lines += ["        }", "    }", "}"]
        }
        lines += [
            "",
            "/// Hands its content the theme of the environment it is placed in: a subtree that sets its",
            "/// own theme with `penTheme(…)` reads it through one, since the view around it reads its own.",
            "public struct PenThemeReader<Content: View>: View {",
            "    @Environment(\\.penTheme) private var theme",
            "    private let content: (PenTheme) -> Content",
            "",
            "    /// A reader whose content is built from the theme.",
            "    public init(@ViewBuilder content: @escaping (PenTheme) -> Content) {",
            "        self.content = content",
            "    }",
            "",
            "    public var body: some View {",
            "        content(theme)",
            "    }",
            "}",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The environment value whose `axis` is the colour scheme, and the axis's mapping to it.
    private func bridgedEnvironment(_ axis: Axis) -> [String] {
        let type = "PenTheme.\(axis.typeName)"
        let dark = axis.options.first { $0.value.lowercased() == "dark" }?.member ?? ".dark"
        let light = axis.options.first { $0.value.lowercased() == "light" }?.member ?? ".light"
        return [
            "public extension EnvironmentValues {",
            "    /// The theme views draw with. Its `\(axis.name)` is the colour scheme: reading it reads",
            "    /// `colorScheme`, and setting it sets `colorScheme`.",
            "    var penTheme: PenTheme {",
            "        get {",
            "            var theme = penThemeAxes",
            "            theme.\(axis.property) = \(type)(colorScheme)",
            "            return theme",
            "        }",
            "        set {",
            "            penThemeAxes = newValue",
            "            colorScheme = newValue.\(axis.property).colorScheme",
            "        }",
            "    }",
            "}",
            "",
            "extension EnvironmentValues {",
            "    /// The theme as last set; ``penTheme`` reads its `\(axis.name)` from the colour scheme instead.",
            "    @Entry var penThemeAxes = PenTheme()",
            "}",
            "",
            "public extension \(type) {",
            "    /// The option a colour scheme selects.",
            "    init(_ colorScheme: ColorScheme) {",
            "        self = colorScheme == .dark ? \(dark) : \(light)",
            "    }",
            "",
            "    /// The colour scheme this option draws in.",
            "    var colorScheme: ColorScheme {",
            "        self == \(dark) ? .dark : .light",
            "    }",
            "}",
        ]
    }
}
