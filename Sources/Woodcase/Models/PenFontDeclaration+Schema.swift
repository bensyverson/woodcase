//
//  PenFontDeclaration+Schema.swift
//  Woodcase
//

import Foundation

/// The key table of the root `fonts` array, declared beside the decoder that reads it.
public extension PenFontDeclaration {
    /// One entry of the root `fonts` array, as `woodcase schema` prints it.
    static let schema = PenNestedShape(
        name: "fonts",
        singular: "a font declaration",
        plural: "an array of font declarations",
        summary: "the root array of font files the document ships; a text node's fontFamily names one",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "name", forms: [.text(.plain)], isRequired: true),
                PenNestedShape.Field(key: "url", forms: [.text(.plain)], isRequired: true),
                PenNestedShape.Field(key: "style", forms: Style.allCases.map { .spelling($0.rawValue) }),
                PenNestedShape.Field(key: "weight", forms: [.number, .slots(["min", "max"])]),
            ]),
        ]
    )
}
