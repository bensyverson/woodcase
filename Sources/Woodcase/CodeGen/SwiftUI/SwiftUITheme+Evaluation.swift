//
//  SwiftUITheme+Evaluation.swift
//  Woodcase
//

extension SwiftUITheme {
    /// Evaluate every variable under every combination of axis options and record a token
    /// for each that has a value, of its type, under all of them; the rest are named in
    /// ``problems``.
    mutating func evaluate(_ variables: [VariableInfo], taken: inout Set<String>) {
        let definitions = Dictionary(variables.map { ($0.name, Self.definition($0)) }) { first, _ in first }
        let combinations = combinations()
        let tables = combinations.map { combination in
            var theme: [String: String] = [:]
            for (axis, option) in zip(axes, combination) {
                theme[axis.name] = axis.options[option].value
            }
            return PenVariableResolver.buildTable(from: definitions, theme: theme, overrides: [:])
        }
        for variable in variables {
            var values: [Token.Case] = []
            for (combination, table) in zip(combinations, tables) {
                guard let value = table[variable.name], let written = Self.code(value, type: variable.type) else { break }
                values.append(Token.Case(
                    options: combination, code: written.code, number: written.number, string: written.string, opaque: written.opaque
                ))
            }
            guard values.count == combinations.count else {
                problems.append("the variable $\(variable.name), which has no \(variable.type.rawValue) value under every theme")
                continue
            }
            let dependent = axes.indices.filter { Self.varies(values, along: $0) }
            let cases = values
                .filter { value in axes.indices.allSatisfy { dependent.contains($0) || value.options[$0] == 0 } }
                .map { value in
                    Token.Case(
                        options: dependent.map { value.options[$0] }, code: value.code, number: value.number,
                        string: value.string, opaque: value.opaque
                    )
                }
            tokens[variable.name] = Token(
                variable: variable.name,
                property: Self.unique(SwiftUIProp.identifier(variable.name), in: &taken),
                type: variable.type,
                axes: dependent,
                cases: cases
            )
        }
    }

    /// Every combination of option indices, one per axis, the first axis outermost; one
    /// empty combination when there are no axes.
    private func combinations() -> [[Int]] {
        axes.reduce([[]]) { partial, axis in
            partial.flatMap { prefix in axis.options.indices.map { prefix + [$0] } }
        }
    }

    /// Whether some two combinations differing only on `axis` give different values.
    private static func varies(_ values: [Token.Case], along axis: Int) -> Bool {
        var seen: [[Int]: String] = [:]
        for value in values {
            var others = value.options
            others[axis] = -1
            if let code = seen[others], code != value.code { return true }
            seen[others] = value.code
        }
        return false
    }

    /// The manifest's variable back as a definition the resolver reads; an unconditioned
    /// value is the unconditional default again.
    private static func definition(_ variable: VariableInfo) -> PenVariable {
        guard variable.isThemed else {
            return PenVariable(type: variable.type, value: .simple(variable.values.first?.value ?? .null))
        }
        return PenVariable(type: variable.type, value: .themed(variable.values.map {
            PenThemedValue(value: $0.value, theme: $0.conditions.isEmpty ? nil : $0.conditions)
        }))
    }

    /// A value's Swift literal for a token of `type`, or `nil` when it is not of the type.
    private static func code(_ value: AnyCodable, type: PenVariableType) -> (code: String, number: Double?, string: String?, opaque: Bool)? {
        switch (type, value) {
        case let (.color, .string(hex)):
            guard let color = PenHexColor(hex) else { return nil }
            return (SwiftUILiteral.color(color), nil, nil, color.alpha == 255)
        case let (.number, .int(number)):
            return (SwiftUILiteral.number(Double(number)), Double(number), nil, false)
        case let (.number, .double(number)):
            return (SwiftUILiteral.number(number), number, nil, false)
        case let (.string, .string(text)):
            return text.hasPrefix("$") ? nil : (SwiftUILiteral.string(text), nil, text, false)
        case let (.boolean, .bool(flag)):
            return (flag ? "true" : "false", nil, nil, false)
        default:
            return nil
        }
    }
}
