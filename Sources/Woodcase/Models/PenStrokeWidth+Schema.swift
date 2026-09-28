//
//  PenStrokeWidth+Schema.swift
//  Woodcase
//

import Foundation

/// The key table the per-side form of `strokeWidth` takes.
///
/// Declared beside the decoder so the four sides it reads and the four the help prints
/// cannot come apart; `PenSchemaTests` writes the object through the decoder and checks
/// the values land on the sides this table names.
public extension PenStrokeWidth {
    /// The object form: a width for each side, any of which may be left out.
    static let schema = PenNestedShape(
        name: "per-side width",
        singular: "an object of per-side widths",
        plural: "an array of per-side width objects",
        summary: "one width per edge; an edge left out carries no stroke",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "top", forms: [.number, .variable(.number)]),
                PenNestedShape.Field(key: "right", forms: [.number, .variable(.number)]),
                PenNestedShape.Field(key: "bottom", forms: [.number, .variable(.number)]),
                PenNestedShape.Field(key: "left", forms: [.number, .variable(.number)]),
            ]),
        ]
    )
}
