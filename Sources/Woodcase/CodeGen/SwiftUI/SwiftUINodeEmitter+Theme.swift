//
//  SwiftUINodeEmitter+Theme.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// The token for the variable `name` read as a `type`, its read noted; `nil`, with the
    /// reason in `unemitted`, when the document has no such variable of that type.
    func token(_ name: String, as type: PenVariableType, unemitted: inout [String]) -> SwiftUITheme.Token? {
        guard let token = scope.theme?.tokens[name] else {
            unemitted.append("the \(type.noun) variable $\(name)")
            return nil
        }
        guard token.type == type else {
            unemitted.append("the \(token.type.noun) variable $\(name) as a \(type.noun)")
            return nil
        }
        themeReads.note()
        return token
    }

    /// A colour's code, and whether it is opaque under every theme; `nil` for one this
    /// emitter cannot write (reported in `unemitted`).
    func colorCode(_ color: PenValue<String>, unemitted: inout [String]) -> (code: String, opaque: Bool)? {
        switch color {
        case let .literal(hex):
            guard let parsed = PenHexColor(hex) else {
                unemitted.append("the colour \(SwiftUILiteral.string(hex))")
                return nil
            }
            return (SwiftUILiteral.color(parsed), parsed.alpha == 255)
        case let .variable(name):
            guard let token = token(name, as: .color, unemitted: &unemitted) else { return nil }
            return (token.read, token.cases.allSatisfy(\.opaque))
        }
    }

    /// A length, literal or read through the theme; `nil` for a variable the theme has no
    /// number for (reported in `unemitted`).
    func number(_ value: PenValue<Double>, unemitted: inout [String]) -> SwiftUINumber? {
        switch value {
        case let .literal(number): SwiftUINumber(number)
        case let .variable(name): token(name, as: .number, unemitted: &unemitted).map(SwiftUINumber.init(token:))
        }
    }

    /// `value`, or zero for one a node leaves out — a shadow's offset, an effect's radius,
    /// a per-side stroke width's missing side; `nil` for the same reason as
    /// ``number(_:unemitted:)``.
    func number(_ value: PenValue<Double>?, unemitted: inout [String]) -> SwiftUINumber? {
        guard let value else { return SwiftUINumber(0) }
        return number(value, unemitted: &unemitted)
    }

    /// A string, as a literal or read through the theme; `nil` for a variable the theme has
    /// no string for (reported in `unemitted`).
    func string(_ value: PenValue<String>, unemitted: inout [String]) -> String? {
        switch value {
        case let .literal(text): SwiftUILiteral.string(text)
        case let .variable(name): token(name, as: .string, unemitted: &unemitted)?.read
        }
    }

    /// `value`, set by an instance's override, as `prop`'s argument: a colour variable is
    /// the caller's read of the theme (`Swatch(tint: theme.accent)`); `nil` when it cannot
    /// be written.
    func argument(_ value: PropMapper.Value, to prop: SwiftUIProp) -> String? {
        guard prop.kind == .color, case let .color(.variable(name)) = value else { return prop.argument(value) }
        var unemitted: [String] = []
        return token(name, as: .color, unemitted: &unemitted)?.read
    }

    /// `view` under the theme `node` sets, when it is a context node: `.penTheme(mode: .dark)`,
    /// and, when anything drawn since `mark` reads the theme, a `PenThemeReader` around it
    /// that hands those reads the theme the modifier sets. An axis or option the document
    /// does not declare is reported and ignored.
    func themed(_ view: SwiftUIViewCode, _ node: PenNode, since mark: Int) -> SwiftUIViewCode {
        guard let settings = node.common.theme, !settings.isEmpty else { return view }
        let axes = scope.theme?.axes ?? []
        var arguments: [String] = []
        var unknown: [String] = []
        for axis in axes {
            guard let value = settings[axis.name] else { continue }
            if let option = axis.option(value) {
                arguments.append("\(axis.property): \(option.member)")
            } else {
                unknown.append("the \(axis.name) option \(SwiftUILiteral.string(value))")
            }
        }
        for name in settings.keys.sorted() where !axes.contains(where: { $0.name == name }) {
            unknown.append("the theme axis \(SwiftUILiteral.string(name)), which the document does not declare")
        }
        warnUnemitted(node, unknown)
        guard !arguments.isEmpty else { return view }
        var wrapped = view
        if themeReads.count > mark {
            themeReads.rollBack(to: mark)
            wrapped = SwiftUIViewCode(head: "PenThemeReader", parameters: "theme", body: [view])
        }
        return wrapped.modified(".penTheme(\(arguments.joined(separator: ", ")))")
    }
}

private extension PenVariableType {
    /// The type as a diagnostic names it.
    var noun: String {
        switch self {
        case .color: "colour"
        case .number: "number"
        case .string: "string"
        case .boolean: "boolean"
        }
    }
}
