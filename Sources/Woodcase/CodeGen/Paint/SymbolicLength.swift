//
//  SymbolicLength.swift
//  Woodcase
//

/// A length an emitter can do arithmetic on without resolving variables: points plus
/// multiples of document variables, so a stroke width bound to a variable still halves,
/// sums and negates.
///
/// Codegen keeps variables symbolic (they become CSS custom properties or theme values
/// in the emitted code), so a length derived from one cannot be a number. Each emitter
/// writes it in its own syntax; React's is `SymbolicLength+CSS.swift`.
struct SymbolicLength: Friendly {
    /// One `variable × factor` term.
    struct Term: Friendly {
        /// The document variable's name, without the leading `$`.
        var variable: String
        /// What the variable's value is multiplied by.
        var factor: Double
    }

    /// The fixed part, in points.
    var points: Double

    /// The variable part, sorted by variable name so equal lengths compare and render alike.
    var terms: [Term]

    /// Zero.
    static let zero = SymbolicLength(points: 0)

    /// Creates a length from a fixed part and variable terms, dropping zero terms.
    init(points: Double, terms: [Term] = []) {
        self.points = points
        self.terms = terms.filter { $0.factor != 0 }.sorted { $0.variable < $1.variable }
    }

    /// Creates a length from a .pen number: a literal is points, a variable one term.
    init(_ value: PenValue<Double>) {
        switch value {
        case let .literal(points): self.init(points: points)
        case let .variable(name): self.init(points: 0, terms: [Term(variable: name, factor: 1)])
        }
    }

    /// Whether the length is exactly zero.
    var isZero: Bool {
        points == 0 && terms.isEmpty
    }

    /// The length in points, when it has no variable part.
    var literalPoints: Double? {
        terms.isEmpty ? points : nil
    }

    /// The length multiplied by `factor`.
    func scaled(by factor: Double) -> SymbolicLength {
        SymbolicLength(points: points * factor, terms: terms.map { Term(variable: $0.variable, factor: $0.factor * factor) })
    }

    /// The sum of two lengths.
    static func + (lhs: SymbolicLength, rhs: SymbolicLength) -> SymbolicLength {
        var factors: [String: Double] = [:]
        for term in lhs.terms + rhs.terms {
            factors[term.variable, default: 0] += term.factor
        }
        return SymbolicLength(
            points: lhs.points + rhs.points,
            terms: factors.map { Term(variable: $0.key, factor: $0.value) }
        )
    }

    /// The difference of two lengths.
    static func - (lhs: SymbolicLength, rhs: SymbolicLength) -> SymbolicLength {
        lhs + rhs.scaled(by: -1)
    }
}
