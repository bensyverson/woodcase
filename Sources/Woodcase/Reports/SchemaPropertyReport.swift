//
//  SchemaPropertyReport.swift
//  Woodcase
//

import Foundation

/// One property row of the .pen vocabulary, flattened for a machine reader.
///
/// ``PenSchemaTable/Property`` is modelled for the decoders — ``PenPropertyShape`` and
/// ``PenValueForm`` are unions whose synthesised encoding (`{"text":{"_0":"color"}}`)
/// is not an interface anyone should have to parse. This carries the same facts flat:
/// the union as one string, the spellings as an array, the variable type as a name, so
/// a caller reads one field per question.
///
/// This is the one struct the CLI's `woodcase schema --json` and a script's
/// `doc.schema()` both publish, so the two cannot drift.
public struct SchemaPropertyReport: Friendly {
    /// Flattens one row of a ``PenSchemaTable``.
    ///
    /// - Parameter property: The row to publish.
    public init(_ property: PenSchemaTable.Property) {
        path = property.path
        key = property.key.written
        value = property.value
        values = property.spellings
        variable = property.variable?.rawValue
        nested = property.nested.map(\.name)
        example = property.example
    }

    /// The codec path `set` and `cp` accept.
    public let path: String

    /// The key the .pen file writes the value under, or absent when the value has no
    /// key of its own and is spread across the node's top-level keys.
    public let key: String?

    /// Every accepted form as one union, exactly as the text table prints it.
    public let value: String

    /// The exact spellings an enumerated property accepts; empty otherwise.
    public let values: [String]

    /// The variable type a `$name` written here must have, or absent.
    public let variable: String?

    /// The names of the nested key tables this property references.
    public let nested: [String]

    /// A literal this property accepts, or absent.
    public let example: String?
}
