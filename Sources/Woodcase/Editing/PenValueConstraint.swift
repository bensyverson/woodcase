//
//  PenValueConstraint.swift
//  Woodcase
//

import Foundation

/// The range, step and unit a numeric property's value must keep to when it is written.
///
/// A ``PenPropertyShape`` says which *forms* a property takes — a number, a spelling, a
/// `$variable`; this says which *numbers*. ``EditPlanner`` refuses a write outside it
/// with ``EditRefusal/Code/outOfRange`` or ``EditRefusal/Code/offStep``, and `woodcase
/// schema` prints ``summary`` for each property that has one.
///
/// It is a write rule, never a read rule: a file holding an opacity of 7 still opens,
/// and an operation applied without planning (a merge, an undo) is not checked.
///
/// ```swift
/// let opacity = PenValueConstraint(unit: .fraction, minimum: .inclusive(0), maximum: .inclusive(1))
/// opacity.violation(by: 7) // .aboveMaximum
/// opacity.summary          // "0 to 1, a fraction"
/// ```
public struct PenValueConstraint: Friendly {
    /// What a property's numbers count.
    public enum Unit: String, Friendly, CaseIterable {
        /// Points, the format's unit of length.
        case points

        /// Degrees of rotation.
        case degrees

        /// A fraction from 0 to 1 — an opacity, a ring's inner radius.
        case fraction

        /// A multiple of the node's `fontSize`, which is what `lineHeight` is.
        case fontSizeMultiple

        /// A count of things — a polygon's sides.
        case count

        /// A scale factor — a browser's zoom.
        case factor

        /// A variable font's weight axis.
        case fontWeight

        /// How the unit reads after a number range.
        var phrase: String {
            switch self {
            case .points: "in points"
            case .degrees: "in degrees"
            case .fraction: "a fraction"
            case .fontSizeMultiple: "a multiple of fontSize, not points"
            case .count: "a count"
            case .factor: "a scale factor"
            case .fontWeight: "a font weight"
            }
        }
    }

    /// One end of a range.
    public struct Bound: Friendly {
        /// Creates a bound.
        ///
        /// - Parameters:
        ///   - value: The limit.
        ///   - isInclusive: Whether the limit itself is allowed.
        public init(value: Double, isInclusive: Bool) {
            self.value = value
            self.isInclusive = isInclusive
        }

        /// A bound the limit itself satisfies.
        public static func inclusive(_ value: Double) -> Bound {
            Bound(value: value, isInclusive: true)
        }

        /// A bound the limit itself does not satisfy.
        public static func exclusive(_ value: Double) -> Bound {
            Bound(value: value, isInclusive: false)
        }

        /// The limit.
        public var value: Double

        /// Whether the limit itself is allowed.
        public var isInclusive: Bool
    }

    /// How a number breaks a constraint.
    public enum Violation: String, Friendly, CaseIterable {
        /// It is below the minimum.
        case belowMinimum

        /// It is above the maximum.
        case aboveMaximum

        /// It is not a whole number of steps.
        case offStep
    }

    /// Creates a constraint.
    ///
    /// - Parameters:
    ///   - unit: What the numbers count.
    ///   - minimum: The lowest value allowed, or `nil` for none.
    ///   - maximum: The highest value allowed, or `nil` for none.
    ///   - step: The increment every value must be a whole multiple of, or `nil`.
    public init(unit: Unit, minimum: Bound? = nil, maximum: Bound? = nil, step: Double? = nil) {
        self.unit = unit
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
    }

    /// What the numbers count.
    public var unit: Unit

    /// The lowest value allowed, or `nil` for none.
    public var minimum: Bound?

    /// The highest value allowed, or `nil` for none.
    public var maximum: Bound?

    /// The increment every value must be a whole multiple of, or `nil` for any number.
    public var step: Double?

    /// Whether the constraint limits values at all, rather than only naming their unit.
    public var limitsValues: Bool {
        minimum != nil || maximum != nil || step != nil
    }

    /// How a number breaks this constraint, or `nil` when it keeps to it.
    ///
    /// - Parameter number: The number written.
    /// - Returns: The first broken rule — range before step.
    public func violation(by number: Double) -> Violation? {
        if let minimum, number < minimum.value || (!minimum.isInclusive && number == minimum.value) {
            return .belowMinimum
        }
        if let maximum, number > maximum.value || (!maximum.isInclusive && number == maximum.value) {
            return .aboveMaximum
        }
        if let step, step > 0 {
            let steps = number / step
            if abs(steps - steps.rounded()) > 1e-9 { return .offStep }
        }
        return nil
    }

    /// The allowed value nearest a refused one: rounded to a step, then held to the range.
    ///
    /// - Parameter number: The number written.
    /// - Returns: The nearest value the constraint takes, or `nil` when the nearest one
    ///   would be an exclusive bound, which has no nearest value.
    public func nearestAllowed(to number: Double) -> Double? {
        var value = number
        if let step, step > 0 { value = (value / step).rounded() * step }
        if let minimum, value < minimum.value { value = minimum.value }
        if let maximum, value > maximum.value { value = maximum.value }
        return violation(by: value) == nil ? value : nil
    }

    /// The constraint as one phrase: `"0 to 1, a fraction"`, `"≥ 0, in points"`,
    /// `"whole numbers ≥ 3, a count"`.
    public var summary: String {
        var parts: [String] = []
        if let range = rangePhrase { parts.append(range) }
        parts.append(unit.phrase)
        return parts.joined(separator: ", ")
    }

    // MARK: - Private

    /// The range in one phrase, or `nil` when the constraint has no bounds or step.
    private var rangePhrase: String? {
        let whole = step == 1 ? "whole numbers " : (step.map { "steps of \(Self.spell($0)) " } ?? "")
        switch (minimum, maximum) {
        case let (low?, high?) where low.isInclusive && high.isInclusive:
            return "\(whole)\(Self.spell(low.value)) to \(Self.spell(high.value))"
        case let (low?, high?):
            return "\(whole)\(Self.phrase(low, below: true)) and \(Self.phrase(high, below: false))"
        case let (low?, nil):
            return "\(whole)\(Self.phrase(low, below: true))"
        case let (nil, high?):
            return "\(whole)\(Self.phrase(high, below: false))"
        case (nil, nil):
            return whole.isEmpty ? nil : String(whole.dropLast())
        }
    }

    /// One bound as a comparison: `≥ 0`, `> 0`, `≤ 10`.
    private static func phrase(_ bound: Bound, below: Bool) -> String {
        let symbol = below ? (bound.isInclusive ? "≥" : ">") : (bound.isInclusive ? "≤" : "<")
        return "\(symbol) \(spell(bound.value))"
    }

    /// A number as a person types it: `1`, never `1.0`.
    static func spell(_ number: Double) -> String {
        number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
    }
}
