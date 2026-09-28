//
//  SwiftUICatalogTextStyle.swift
//  Woodcase
//

/// One text style a document sets — family, size, weight and slant — as the catalog's type
/// section shows it: a caption naming the style over a line set in it.
///
/// A family or size that names a variable is read through the theme, so the specimen moves
/// with the catalog's theme picker as the views' text does.
struct SwiftUICatalogTextStyle: Friendly {
    /// The family's Swift expression — `"Inter"` or `theme.fontPrimary` — or `nil` for the
    /// system font.
    var family: String?

    /// The size's Swift expression: `14` or `theme.fontSizeBody`.
    var size: String

    /// The CSS weight: 400 regular, 700 bold.
    var weight: Double

    /// Whether the style is italic.
    var italic: Bool

    /// The caption: the family and size as the .pen file writes them, then the weight —
    /// `$font-primary 14 600`.
    var label: String

    /// The size in points under the default theme, which orders the ramp.
    var points: Double

    /// Whether the style reads the theme.
    var readsTheme: Bool {
        family?.hasPrefix("theme.") == true || size.hasPrefix("theme.")
    }

    /// The `.penFont(…)` modifier that sets a line in this style, writing only what differs
    /// from its defaults as the text emitter does.
    var fontModifier: String {
        var arguments = family.map { [$0] } ?? []
        arguments.append("size: \(size)")
        if weight != 400 {
            arguments.append("weight: \(SwiftUILiteral.number(weight))")
        }
        if italic {
            arguments.append("italic: true")
        }
        return ".penFont(\(arguments.joined(separator: ", ")))"
    }

    /// Every distinct style the text nodes under `roots` set, largest first, then heaviest,
    /// then by caption; a variable `theme` has no token for is left at its default.
    static func styles(in roots: [PenNode], theme: SwiftUITheme?) -> [Self] {
        var styles: Set<Self> = []
        var pending = roots
        while let node = pending.popLast() {
            if case let .text(data) = node.kind {
                styles.insert(Self(data, theme: theme))
            }
            pending.append(contentsOf: node.kind.inlineChildrenIfPresent ?? [])
        }
        return styles.sorted {
            ($1.points, $1.weight, $0.label) < ($0.points, $0.weight, $1.label)
        }
    }

    /// The style `data` sets.
    private init(_ data: PenNode.TextData, theme: SwiftUITheme?) {
        var labels: [String] = []
        switch data.fontFamily {
        case let .literal(name)?:
            family = SwiftUILiteral.string(name)
            labels.append(name)
        case let .variable(name)?:
            let token = theme?.tokens[name].flatMap { $0.type == .string ? $0 : nil }
            family = token?.read
            labels.append(token == nil ? "system" : "$\(name)")
        case nil:
            family = nil
            labels.append("system")
        }
        switch data.fontSize {
        case let .literal(value)?:
            size = SwiftUILiteral.number(value)
            points = value
            labels.append(size)
        case let .variable(name)?:
            let token = theme?.tokens[name].flatMap { $0.type == .number ? $0 : nil }
            points = token?.cases.first?.number ?? PenTextMeasurer.defaultFontSize
            size = token?.read ?? SwiftUILiteral.number(points)
            labels.append(token == nil ? size : "$\(name)")
        case nil:
            points = PenTextMeasurer.defaultFontSize
            size = SwiftUILiteral.number(points)
            labels.append(size)
        }
        weight = data.fontWeight?.literalValue.map(PenFontWeight.cssWeight) ?? 400
        labels.append(SwiftUILiteral.number(weight))
        italic = data.fontStyle?.literalValue?.lowercased() == "italic"
        if italic {
            labels.append("italic")
        }
        label = labels.joined(separator: " ")
    }
}
