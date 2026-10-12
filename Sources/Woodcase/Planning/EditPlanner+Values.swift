//
//  EditPlanner+Values.swift
//  Woodcase
//

import Foundation

/// The value rules a write is held to: a property's ``PenValueConstraint``, and the
/// variable a `$name` binds.
///
/// Judged per property against the shape table, so a set's `common.opacity` and an
/// override's `opacity` meet the same rule. A value equal to what the node already holds
/// is let through: loading is lenient, and reading a property and writing it straight
/// back must stay a no-op even when the file broke a rule.
extension EditPlanner {
    /// One property a write would store.
    struct ValueWrite {
        /// The key as the write names it: a property path, or a raw override key.
        var key: String

        /// The field the shape table is keyed by.
        var field: String

        /// The value as it would be stored, after coercion.
        var value: AnyCodable

        /// What the node holds there now, if anything.
        var current: AnyCodable?
    }

    /// Refuses the first value that breaks its property's constraint or binds a variable
    /// it should not.
    ///
    /// - Parameters:
    ///   - writes: The values, in the order they should be judged.
    ///   - kind: The kind of the node written, which decides whether text content
    ///     forgives an undefined `$name`.
    ///   - address: The address as written, for the refusal.
    ///   - document: The document, for its variables.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/outOfRange``,
    ///   ``EditRefusal/Code/offStep``, ``EditRefusal/Code/undefinedVariable`` or
    ///   ``EditRefusal/Code/variableTypeMismatch``.
    static func checkValues(
        _ writes: [ValueWrite],
        on kind: PenNode.Kind,
        address: String,
        in document: EditableDocument
    ) throws {
        if case .unknown = kind { return }
        for write in writes {
            if case .null = write.value { continue }
            if write.value == write.current { continue }
            guard let shape = NodePropertyCodec.shape(of: write.field) else { continue }
            try checkBindings(write, shape: shape, address: address, in: document)
            if let constraint = shape.constraint {
                try checkConstraint(write, constraint, address: address)
            }
        }
    }

    /// Refuses a binding, wherever it is required: one the document does not define, or
    /// one of a type the property does not take.
    ///
    /// - Parameters:
    ///   - property: The property path or raw key, for the refusal.
    ///   - variable: The variable name, without `$`.
    ///   - expected: The type the property's binding must have, or `nil` to check only
    ///     that the variable exists.
    ///   - address: The address as written.
    ///   - document: The document, for its variables.
    /// - Throws: ``EditRefusal``.
    static func checkBinding(
        _ property: String,
        to variable: String,
        expecting expected: PenVariableType?,
        address: String,
        in document: EditableDocument
    ) throws {
        let reference = PenDollarEscape.dollar + variable
        guard let defined = document.variable(named: variable) else {
            guard !document.mayDefineImported(variable) else { return }
            throw EditRefusal(
                code: .undefinedVariable,
                address: address,
                property: property,
                expected: expected.map(phrase(of:)),
                message: "\(address) \(property) refers to \(reference), and the document defines no "
                    + "variable named \(variable) — define it first with `woodcase vars set <file> "
                    + "\(variable)=<value>`, or write \(PenDollarEscape.sequence)\(variable) for the literal text"
            )
        }
        guard let expected, defined.type != expected else { return }
        throw EditRefusal(
            code: .variableTypeMismatch,
            address: address,
            property: property,
            expected: phrase(of: expected),
            message: "\(address) \(property) takes \(phrase(of: expected)), but \(variable) is a "
                + "\(defined.type.rawValue) variable — bind a \(expected.rawValue) variable instead; "
                + "`woodcase vars <file>` lists them"
                + (expected == .string ? ", or write \(PenDollarEscape.sequence)\(variable) for the literal text" : "")
        )
    }

    // MARK: - Private

    /// The variable references a value carries, and the rules they are held to.
    private static func checkBindings(
        _ write: ValueWrite,
        shape: PenPropertyShape,
        address: String,
        in document: EditableDocument
    ) throws {
        // A property that takes no variable stores `$word` as the text it is.
        guard let expected = shape.variable else { return }
        if let name = reference(in: write.value) {
            // Text content alone reads a `$word` the document defines nowhere as the
            // words it is — `$30.00` is a price — so only a name it defines is judged.
            if forgivesUndefined(write.field), document.variable(named: name) == nil { return }
            try checkBinding(write.key, to: name, expecting: expected, address: address, in: document)
            return
        }
        // References nested inside a structured value — a fill object's color — must
        // name a variable; their type is the nested key's, which the table does not say.
        for name in nestedReferences(in: write.value) {
            try checkBinding(write.key, to: name, expecting: nil, address: address, in: document)
        }
    }

    /// Refuses a number outside the property's constraint, at the top level or in a slot.
    private static func checkConstraint(
        _ write: ValueWrite,
        _ constraint: PenValueConstraint,
        address: String
    ) throws {
        for number in numbers(in: write.value) {
            guard let violation = constraint.violation(by: number) else { continue }
            let spelled = PenValueConstraint.spell(number)
            let suggestion = constraint.nearestAllowed(to: number)
                .map { "\(write.key)=\(PenValueConstraint.spell($0))" }
            let remedy = suggestion.map { " — the nearest is `\($0)`" }
                ?? " — `woodcase schema` prints every property's range"
            throw EditRefusal(
                code: violation == .offStep ? .offStep : .outOfRange,
                address: address,
                property: write.key,
                expected: constraint.summary,
                suggestion: suggestion,
                message: "\(address) \(write.key) is \(spelled), but it takes \(constraint.summary)\(remedy)"
            )
        }
    }

    /// The variable name a whole value references, or `nil`.
    private static func reference(in value: AnyCodable) -> String? {
        guard case let .string(text) = value,
              text.hasPrefix(PenDollarEscape.dollar),
              !text.hasPrefix(PenDollarEscape.sequence)
        else { return nil }
        let name = String(text.dropFirst())
        return name.isEmpty ? nil : name
    }

    /// Every variable name referenced inside an array or object, at any depth.
    private static func nestedReferences(in value: AnyCodable) -> [String] {
        switch value {
        case let .array(items): items.flatMap { reference(in: $0).map { [$0] } ?? nestedReferences(in: $0) }
        case let .dictionary(entries):
            entries.keys.sorted().flatMap { key in
                let item = entries[key] ?? .null
                return reference(in: item).map { [$0] } ?? nestedReferences(in: item)
            }
        default: []
        }
    }

    /// The numbers a constraint applies to: the value itself, or each slot of a
    /// per-corner, per-side or per-edge value.
    private static func numbers(in value: AnyCodable) -> [Double] {
        switch value {
        case let .int(number): [Double(number)]
        case let .double(number): [number]
        case let .array(items): items.compactMap(scalar)
        case let .dictionary(entries): entries.keys.sorted().compactMap { entries[$0].flatMap(scalar) }
        default: []
        }
    }

    /// A number standing alone, or `nil`.
    private static func scalar(_ value: AnyCodable) -> Double? {
        switch value {
        case let .int(number): Double(number)
        case let .double(number): number
        default: nil
        }
    }

    /// Whether a field reads an undefined `$word` as literal text.
    ///
    /// The rule ``PenVariableResolver`` applies to text content, and only there.
    private static func forgivesUndefined(_ field: String) -> Bool {
        field == contentField
    }

    /// The text content field.
    private static let contentField = "content"

    /// How a binding's required type reads: `a $color variable`.
    private static func phrase(of type: PenVariableType) -> String {
        "a \(PenDollarEscape.dollar)\(type.rawValue) variable"
    }
}
