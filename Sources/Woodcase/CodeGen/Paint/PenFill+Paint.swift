//
//  PenFill+Paint.swift
//  Woodcase
//

extension PenFill {
    /// Whether the fill paints: an explicit `enabled: false` switches it off, and a fill
    /// of a type the model does not know never paints.
    var isEnabled: Bool {
        switch self {
        case .shorthand: true
        case let .color(c): c.enabled?.literalValue != false
        case let .gradient(g): g.enabled?.literalValue != false
        case let .image(i): i.enabled?.literalValue != false
        case let .meshGradient(m): m.enabled?.literalValue != false
        case let .shader(s): s.enabled?.literalValue != false
        case .unknown: false
        }
    }

    /// The fill's own blend mode; a shorthand colour has none.
    var blendMode: PenBlendMode? {
        switch self {
        case .shorthand: nil
        case let .color(c): c.blendMode
        case let .gradient(g): g.blendMode
        case let .image(i): i.blendMode
        case let .meshGradient(m): m.blendMode
        case let .shader(s): s.blendMode
        case .unknown: nil
        }
    }

    /// The colour of a solid fill — a literal, or a document variable for a `$name`
    /// shorthand or colour reference — or `nil` for any other kind of fill.
    var solidColor: PenValue<String>? {
        switch self {
        case let .shorthand(color):
            color.hasPrefix("$") ? .variable(String(color.dropFirst())) : .literal(color)
        case let .color(colorFill):
            colorFill.color
        default:
            nil
        }
    }
}
