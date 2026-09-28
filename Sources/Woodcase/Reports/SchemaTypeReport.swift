//
//  SchemaTypeReport.swift
//  Woodcase
//

import Foundation

/// One node type's schema, flattened for a machine reader.
///
/// What `woodcase schema <type> --json` prints, and what a script's `doc.schema(type)`
/// returns. Build one through ``SchemaLookup/type(named:)`` when the type name came
/// from a caller, so an unknown name is refused with the sentence that lists the real
/// ones rather than answered with nothing.
public struct SchemaTypeReport: Friendly {
    /// Builds the payload for one node type.
    ///
    /// - Parameter type: The type to describe.
    public init(type: PenNode.NodeType) {
        let table = PenSchema.table(for: type)
        self.type = type.rawValue
        summary = table.summary
        properties = table.properties.map(SchemaPropertyReport.init)
        nested = table.nested.map(SchemaNestedReport.init)
        common = PenSchema.common.properties.map(\.path)
    }

    /// The node type's name, as a .pen file writes it.
    public let type: String

    /// One phrase saying what a node of this type is.
    public let summary: String

    /// Its `kind.*` properties, sorted by path.
    public let properties: [SchemaPropertyReport]

    /// Every nested key table those properties reference.
    public let nested: [SchemaNestedReport]

    /// The `common.*` paths every node also takes, as paths only — their shapes are in
    /// the overview, and repeating thirteen identical rows on sixteen types is noise.
    public let common: [String]
}
