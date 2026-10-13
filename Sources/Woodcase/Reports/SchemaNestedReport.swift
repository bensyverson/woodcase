//
//  SchemaNestedReport.swift
//  Woodcase
//

import Foundation

/// One nested key table of the .pen vocabulary, flattened for a machine reader.
///
/// The sibling of ``SchemaPropertyReport`` for the shapes a property row references —
/// a fill, a stroke, a shadow — with each arm of a discriminated union spelled out.
public struct SchemaNestedReport: Friendly {
    /// Flattens a nested shape and its variants.
    ///
    /// - Parameter shape: The shape to publish.
    public init(_ shape: PenNestedShape) {
        name = shape.name
        summary = shape.summary
        discriminator = shape.discriminator
        variants = shape.variants.map(Variant.init)
    }

    /// The shape's name, as a property row refers to it.
    public let name: String

    /// One phrase saying what the shape is for.
    public let summary: String

    /// The key whose value picks the variant, or absent for a shape with one form.
    public let discriminator: String?

    /// The arms of the union, in the order the decoder declares them.
    public let variants: [Variant]

    // MARK: - Variant

    /// One arm of a discriminated shape.
    public struct Variant: Friendly {
        /// Flattens one arm.
        ///
        /// - Parameter variant: The arm to publish.
        public init(_ variant: PenNestedShape.Variant) {
            spelling = variant.spelling
            fields = variant.fields.map(Field.init)
        }

        /// The discriminator value that selects this arm, or absent.
        public let spelling: String?

        /// The keys it accepts.
        public let fields: [Field]
    }

    // MARK: - Field

    /// One key inside a nested shape.
    public struct Field: Friendly {
        /// Flattens one key.
        ///
        /// - Parameter field: The key to publish.
        public init(_ field: PenNestedShape.Field) {
            key = field.key
            value = field.value
            values = PenValueForm.spellings(of: field.forms)
            variable = PenValueForm.variableType(of: field.forms)?.rawValue
            required = field.isRequired
            nested = field.forms.compactMap(\.nestedShape).map(\.name)
            constraint = field.constraint?.summary
            self.default = field.default?.value
            if case let .derived(derivation)? = field.default {
                defaultFrom = derivation.phrase
            } else {
                defaultFrom = nil
            }
        }

        /// The key as the .pen file writes it.
        public let key: String

        /// Every accepted form as one union.
        public let value: String

        /// The exact spellings this key accepts; empty otherwise.
        public let values: [String]

        /// The variable type a `$name` written here must have, or absent.
        public let variable: String?

        /// Whether the decoder refuses the object without this key.
        public let required: Bool

        /// The names of the nested key tables this key references.
        public let nested: [String]

        /// The range, step and unit a number written here must keep to, in one phrase —
        /// `"0 to 1, a fraction"` — or absent.
        public let constraint: String?

        /// What the key is when an object leaves it unset, as the file would write it —
        /// `0.5`, `"outer"`, `true` — or absent when it has no literal default.
        public let `default`: AnyCodable?

        /// Where a default no literal states comes from — "the font's own line height" —
        /// or absent.
        public let defaultFrom: String?
    }
}
