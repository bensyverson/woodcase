//
//  PenValue.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// A property value that is either a concrete literal or a variable reference.
///
/// In the .pen format, most properties accept either a direct value or a `$variable` reference.
/// The TypeScript schema represents this as `NumberOrVariable`, `ColorOrVariable`, etc.
/// `PenValue<T>` unifies all of these into a single generic type.
///
/// Variable references are strings prefixed with `$`:
/// ```json
/// { "fill": "$color.primary", "opacity": 0.8, "fontSize": "$size.heading" }
/// ```
///
/// A **string** literal that must itself hold a `$` needs to say so, because the wire
/// format gives a leading `$name` only one meaning. ``PenDollarEscape`` is that
/// convention, and this is where it is read and written:
/// ```json
/// { "content": "\\$v-muted" }
/// ```
/// decodes to `.literal("$v-muted")`, not `.variable("v-muted")`, and a `\$` anywhere
/// else in the string loses its backslash the same way — `Price: \\$30` decodes to
/// `Price: $30`. Encoding is the inverse where the wire form is ambiguous and nowhere
/// else: a literal beginning with `$` is written back with the `\` prefix, while a `$`
/// further into the string is written bare, so Pen.app reads it as the text it is.
/// Only `T == String` values can need any of this — a number, boolean or color
/// variable's *type* never collides with a literal that looks like a reference.
public enum PenValue<T: Friendly>: Sendable, Equatable, Hashable, Codable {
    /// A concrete value.
    case literal(T)
    /// A reference to a named variable (without `$` prefix).
    case variable(String)
}

// MARK: - Convenience

public extension PenValue {
    /// Returns the literal value if this is a `.literal`, otherwise nil.
    var literalValue: T? {
        if case let .literal(value) = self { return value }
        return nil
    }

    /// Returns the variable name (without `$` prefix) if this is a `.variable`, otherwise nil.
    var variableName: String? {
        if case let .variable(name) = self { return name }
        return nil
    }
}

// MARK: - Codable

public extension PenValue {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try string first to detect variable references
        if let stringValue = try? container.decode(String.self) {
            if T.self == String.self, stringValue.hasPrefix(PenDollarEscape.sequence) {
                // A leading `\$` says the whole string is a literal: it is not read as
                // a reference, and its own backslash — like every other `\$` in it — is
                // consumed.
                let literal = PenDollarEscape.unescaped(String(stringValue.dropFirst()))
                // swiftlint:disable:next force_cast
                self = .literal(literal as! T)
            } else if stringValue.hasPrefix(PenDollarEscape.dollar) {
                let name = String(stringValue.dropFirst())
                self = .variable(name)
            } else if T.self == String.self {
                // A plain string literal, not a variable — but a `\$` in it is still
                // the escape, wherever it stands.
                // swiftlint:disable:next force_cast
                self = .literal(PenDollarEscape.unescaped(stringValue) as! T)
            } else {
                throw DecodingError.typeMismatch(
                    T.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected \(T.self) or $variable, got string: \(stringValue)"
                    )
                )
            }
        } else {
            let value = try container.decode(T.self)
            self = .literal(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .literal(value):
            if let stringValue = value as? String {
                // Only a leading `$` is ambiguous on the wire, so only a leading one is
                // written back escaped.
                try container.encode(PenDollarEscape.escaped(stringValue))
            } else {
                try container.encode(value)
            }
        case let .variable(name):
            try container.encode("$\(name)")
        }
    }
}
