//
//  PenNestedShape.swift
//  Woodcase
//

import Foundation

/// The key table of a structured .pen value — a fill, an effect, a per-side stroke width.
///
/// A property whose value is an object is the one an agent cannot guess: "an object" says
/// nothing, and a caller who has to guess writes `{"type":"solid"}` and is refused. So a
/// structured property carries the table itself, and the table is declared **beside the
/// type that decodes it** — ``PenFill/schema``, ``PenEffect/schema``,
/// ``PenStrokeWidth/schema`` — where a field added to the payload is one line away from
/// the row that should describe it. `PenSchemaTests` closes the loop with `Mirror`:
/// a variant whose keys are not the payload's stored properties fails the suite.
///
/// A shape with a ``discriminator`` is a union — a fill's `"type"` picks which set of
/// keys applies — and each ``Variant`` is one arm of it. A shape without one has exactly
/// one variant, whose ``Variant/spelling`` is `nil`.
public struct PenNestedShape: Friendly {
    /// Creates a nested shape.
    ///
    /// - Parameters:
    ///   - name: The shape's name, as the schema table refers to it (`fill`).
    ///   - singular: How a refusal words one of them ("a fill object").
    ///   - plural: How a refusal words an array of them ("an array of fill objects").
    ///   - summary: One phrase saying what the shape is for.
    ///   - discriminator: The key whose value picks the variant, or `nil`.
    ///   - variants: The arms of the union, or one unnamed variant.
    public init(
        name: String,
        singular: String,
        plural: String,
        summary: String,
        discriminator: String? = nil,
        variants: [Variant]
    ) {
        self.name = name
        self.singular = singular
        self.plural = plural
        self.summary = summary
        self.discriminator = discriminator
        self.variants = variants
    }

    /// The shape's name, as the schema table refers to it.
    public let name: String

    /// How a refusal words one of them.
    public let singular: String

    /// How a refusal words an array of them.
    public let plural: String

    /// One phrase saying what the shape is for.
    public let summary: String

    /// The key whose value picks the variant, or `nil` for a shape with one form.
    public let discriminator: String?

    /// The arms of the union, in the order the decoder declares them.
    public let variants: [Variant]

    /// Every nested shape this one references, at any depth, itself first.
    ///
    /// Rendered tables need the closure so a gradient's stops get a table of their own
    /// rather than being called "an object" one level down.
    public var reachable: [PenNestedShape] {
        var seen: Set<String> = [name]
        var result: [PenNestedShape] = [self]
        var queue = variants.flatMap(\.fields).flatMap(\.forms).compactMap(\.nestedShape)
        while let next = queue.first {
            queue.removeFirst()
            guard seen.insert(next.name).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: next.variants.flatMap(\.fields).flatMap(\.forms).compactMap(\.nestedShape))
        }
        return result
    }

    // MARK: - Variant

    /// One arm of a discriminated shape: the spelling that selects it and the keys it takes.
    public struct Variant: Friendly {
        /// Creates one arm.
        ///
        /// - Parameters:
        ///   - spelling: The discriminator value that selects it, or `nil` when the
        ///     shape has no discriminator.
        ///   - fields: The keys this arm accepts, in declaration order.
        public init(spelling: String? = nil, fields: [Field]) {
            self.spelling = spelling
            self.fields = fields
        }

        /// The discriminator value that selects this arm.
        public let spelling: String?

        /// The keys this arm accepts, in the order the payload declares them.
        public let fields: [Field]
    }

    // MARK: - Field

    /// One key inside a nested shape.
    public struct Field: Friendly {
        /// Creates one key's description.
        ///
        /// - Parameters:
        ///   - key: The key as the .pen file writes it.
        ///   - forms: The forms its value may take.
        ///   - isRequired: Whether the decoder refuses the object without it.
        public init(key: String, forms: [PenValueForm], isRequired: Bool = false) {
            self.key = key
            self.forms = forms
            self.isRequired = isRequired
        }

        /// The key as the .pen file writes it.
        public let key: String

        /// The forms its value may take.
        public let forms: [PenValueForm]

        /// Whether the decoder refuses the object without it.
        public let isRequired: Bool

        /// The value column: the forms as one union.
        public var value: String {
            PenValueForm.signature(of: forms)
        }
    }
}
