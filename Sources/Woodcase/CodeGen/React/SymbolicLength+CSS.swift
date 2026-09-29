//
//  SymbolicLength+CSS.swift
//  Woodcase
//

extension SymbolicLength {
    /// The terms as CSS: `4px`, `var(--w)`, `var(--w) * 0.5`.
    ///
    /// A point is a CSS pixel, and a document variable is the custom property of the same
    /// name that `theme.css` declares.
    private var cssParts: [String] {
        var parts: [String] = []
        if points != 0 {
            parts.append("\(ReactEmitter.cssNumber(points))px")
        }
        for term in terms {
            let reference = "var(--\(term.variable))"
            parts.append(term.factor == 1 ? reference : "\(reference) * \(ReactEmitter.cssNumber(term.factor))")
        }
        return parts
    }

    /// The length as a declaration value: `0`, `4px`, `-4px` or `calc(…)` — never with a
    /// unary minus in front of `var()`, which `calc()` rejects.
    var css: String {
        let parts = cssParts
        if parts.isEmpty { return "0" }
        if terms.isEmpty { return parts[0] }
        return "calc(\(parts.joined(separator: " + ")))"
    }

    /// The length as an operand inside another `calc()`, parenthesized when compound.
    var operand: String {
        let parts = cssParts
        if parts.isEmpty { return "0px" }
        return parts.count == 1 ? parts[0] : "(\(parts.joined(separator: " + ")))"
    }

    /// The length as leading terms of a `calc()` sum, without parentheses.
    var sumTerms: String {
        cssParts.joined(separator: " + ")
    }
}
