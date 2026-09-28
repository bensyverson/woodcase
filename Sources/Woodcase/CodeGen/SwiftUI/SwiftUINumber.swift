//
//  SwiftUINumber.swift
//  Woodcase
//

/// A length the emitted code writes: a literal (`16`) or a theme read (`theme.spacingMd`),
/// with the value it takes under every theme, for the decisions that need a number — is it
/// zero, how far does it reach.
struct SwiftUINumber: Friendly {
    /// The expression written into the source.
    var code: String

    /// The value under each theme: one for a literal.
    var values: [Double]

    /// A literal number.
    init(_ value: Double) {
        code = SwiftUILiteral.number(value)
        values = [value]
    }

    /// A number read through the theme.
    init(token: SwiftUITheme.Token) {
        code = token.read
        values = token.cases.compactMap(\.number)
    }

    /// The number, when it is a literal rather than a read.
    var literal: Double? {
        guard values.count == 1, code == SwiftUILiteral.number(values[0]) else { return nil }
        return values[0]
    }

    /// Whether it is zero under every theme.
    var isZero: Bool {
        values.allSatisfy { $0 == 0 }
    }

    /// The largest value it takes.
    var largest: Double {
        values.max() ?? 0
    }

    /// The smallest value it takes.
    var smallest: Double {
        values.min() ?? 0
    }

    /// Half of it: `8` for `16`, `theme.gap / 2` for a read.
    var halved: SwiftUINumber {
        guard let literal else {
            var half = self
            half.code = "\(code) / 2"
            half.values = values.map { $0 / 2 }
            return half
        }
        return SwiftUINumber(literal / 2)
    }

    /// The negative of it: `-8` for `8`, `-theme.gap` for a read.
    var negated: SwiftUINumber {
        guard let literal else {
            var opposite = self
            opposite.code = "-\(code)"
            opposite.values = values.map { -$0 }
            return opposite
        }
        return SwiftUINumber(-literal)
    }
}
