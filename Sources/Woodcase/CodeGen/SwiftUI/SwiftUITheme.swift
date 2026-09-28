//
//  SwiftUITheme.swift
//  Woodcase
//

/// The document's themes and variables as the SwiftUI emitter writes them: `PenTheme`, a
/// value with one enum-typed property per theme axis and one computed property per
/// variable, which views read from the environment.
///
/// Each variable is evaluated under every combination of axis options with the renderer's
/// own rule (``PenVariableResolver``), so a token reads exactly what Pen draws under each
/// theme, chains followed; the token then switches only on the axes its value depends on.
struct SwiftUITheme: Friendly {
    /// A theme axis: a Swift enum of its options and the property that holds one.
    struct Axis: Friendly {
        /// The axis name in the .pen file: `mode`.
        var name: String

        /// The `PenTheme` property: `mode`.
        var property: String

        /// The enum's name: `Mode`.
        var typeName: String

        /// The options, in the file's order; the first is the default.
        var options: [Option]

        /// Whether the axis's options are light and dark, so SwiftUI's colour scheme selects
        /// them.
        var bridgesColorScheme: Bool

        /// One option of an axis.
        struct Option: Friendly {
            /// The option as the .pen file spells it, the enum's raw value.
            var value: String

            /// The case's identifier, back-quoted when it is a keyword: `` `default` ``.
            var caseName: String

            /// The case as an implicit member expression: `.default`.
            var member: String {
                "." + caseName.filter { $0 != "`" }
            }
        }

        /// The option spelled `value`, if the axis has one.
        func option(_ value: String) -> Option? {
            options.first { $0.value == value }
        }
    }

    /// A variable as a computed property of `PenTheme`.
    struct Token: Friendly {
        /// The variable's name in the .pen file.
        var variable: String

        /// The `PenTheme` property: `bgPage`.
        var property: String

        /// The variable's type, which decides the property's Swift type.
        var type: PenVariableType

        /// The indices, in ``SwiftUITheme/axes``, of the axes the value depends on.
        var axes: [Int]

        /// The value under each combination of those axes' options, the first axis's
        /// options outermost.
        var cases: [Case]

        /// One combination of options and the value under it.
        struct Case: Friendly {
            /// The option index on each of the token's axes.
            var options: [Int]

            /// The value's Swift literal: `Color(hex: 0xFFFFFF)`, `16`, `"Inter"`.
            var code: String

            /// The value as a number, for a number token.
            var number: Double?

            /// The value as written, for a string token: a font family's name.
            var string: String?

            /// Whether the value is an opaque colour.
            var opaque: Bool
        }

        /// The property's Swift type.
        var swiftType: String {
            switch type {
            case .color: "Color"
            case .number: "CGFloat"
            case .string: "String"
            case .boolean: "Bool"
            }
        }

        /// The read a view writes: `theme.bgPage`.
        var read: String {
            "theme.\(property)"
        }
    }

    /// The axes, in name order.
    var axes: [Axis]

    /// The tokens by variable name.
    var tokens: [String: Token]

    /// Why variables could not become tokens, for the emitter's warnings.
    var problems: [String]

    /// The axis that follows SwiftUI's colour scheme, if any.
    var bridgedAxis: Axis? {
        axes.first(where: \.bridgesColorScheme)
    }

    /// The tokens in name order, as `PenTheme.swift` declares them.
    var sortedTokens: [Token] {
        tokens.values.sorted { $0.variable < $1.variable }
    }
}

extension SwiftUITheme {
    /// The theme of a document whose analysis is `manifest`, or `nil` when it has neither
    /// axes nor variables.
    init?(_ manifest: ThemeManifest) {
        guard !manifest.axes.isEmpty || !manifest.variables.isEmpty else { return nil }
        // `Hashable`'s own property; a variable named `hash-value` must not redeclare it.
        var taken: Set = ["hashValue"]
        axes = manifest.axes.map { axis in
            let property = SwiftUITheme.unique(SwiftUIProp.identifier(axis.name), in: &taken)
            var caseNames: Set<String> = []
            let options = axis.values.map { value in
                Axis.Option(value: value, caseName: SwiftUITheme.unique(SwiftUITheme.caseName(value), in: &caseNames))
            }
            let lowered = Set(axis.values.map { $0.lowercased() })
            return Axis(
                name: axis.name,
                property: property,
                typeName: SwiftUITheme.typeName(property),
                options: options,
                bridgesColorScheme: lowered == ["light", "dark"] && axis.values.count == 2
            )
        }
        // Only the first light/dark axis bridges: one colour scheme cannot select two.
        if let first = axes.firstIndex(where: \.bridgesColorScheme) {
            for index in axes.indices where index != first {
                axes[index].bridgesColorScheme = false
            }
        }
        tokens = [:]
        problems = []
        evaluate(manifest.variables, taken: &taken)
    }

    /// `base`, or `base` numbered from 2, whichever `taken` does not hold yet; the result
    /// is added to `taken`.
    static func unique(_ base: String, in taken: inout Set<String>) -> String {
        var name = base
        var suffix = 2
        while taken.contains(name) {
            name = base.hasPrefix("`") ? "`\(base.dropFirst().dropLast())\(suffix)`" : "\(base)\(suffix)"
            suffix += 1
        }
        taken.insert(name)
        return name
    }

    /// An option's case name: lower camel case, back-quoted when a keyword; `self`, `init`
    /// and `Type`, which no member expression can name, are suffixed `Option`.
    private static func caseName(_ value: String) -> String {
        let name = SwiftUIProp.identifier(value)
        return ["`self`", "`init`", "Type", "Protocol"].contains(name) ? name.filter { $0 != "`" } + "Option" : name
    }

    /// An axis enum's name: its property's, capitalised.
    private static func typeName(_ property: String) -> String {
        let bare = property.filter { $0 != "`" }
        return bare.prefix(1).uppercased() + bare.dropFirst()
    }
}
