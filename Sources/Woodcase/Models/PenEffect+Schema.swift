//
//  PenEffect+Schema.swift
//  Woodcase
//

import Foundation

/// The key table an `effect` value takes, declared beside the decoder that reads it.
///
/// The spelling an agent gets wrong here is `background_blur` — a blur *behind* a node
/// is not `backdrop`, and the only defense against inventing a name is printing the
/// three the decoder takes. `PenSchemaTests` checks each variant's keys against the
/// payload's own stored properties with `Mirror`.
public extension PenEffect {
    /// An effect object, in every spelling its `type` key takes.
    static let schema = PenNestedShape(
        name: "effect",
        singular: "an effect object",
        plural: "an array of effect objects",
        summary: "a blur, a blur of what is behind the node, or a shadow",
        discriminator: "type",
        variants: [
            PenNestedShape.Variant(
                spelling: "blur",
                fields: [enabledField, radiusField]
            ),
            PenNestedShape.Variant(
                spelling: "background_blur",
                fields: [enabledField, radiusField]
            ),
            PenNestedShape.Variant(
                spelling: "shadow",
                fields: [
                    enabledField,
                    PenNestedShape.Field(
                        key: "shadowType",
                        forms: PenEffect.PenShadowEffect.ShadowType.allCases.map { .spelling($0.rawValue) },
                        default: .string(PenEffect.PenShadowEffect.ShadowType.outer.rawValue)
                    ),
                    PenNestedShape.Field(key: "offset", forms: [.one(offsetSchema)]),
                    PenNestedShape.Field(
                        key: "blur",
                        forms: [.number, .variable(.number)],
                        constraint: .length,
                        default: .number(0)
                    ),
                    PenNestedShape.Field(
                        key: "color",
                        forms: [.text(.color), .variable(.color)],
                        default: .string("#00000080")
                    ),
                    PenNestedShape.Field(
                        key: "blendMode",
                        forms: [.text(.blendMode)],
                        default: .string(PenBlendMode.normal.rawString)
                    ),
                ]
            ),
        ]
    )

    /// How far a shadow is displaced from the node.
    ///
    /// `x` and `y` are both required in an offset object, so each one's default is what
    /// the renderer draws when the shadow leaves `offset` out altogether: 0, 0, the
    /// shadow straight under the node.
    static let offsetSchema = PenNestedShape(
        name: "offset",
        singular: "an offset object",
        plural: "an array of offset objects",
        summary: "how far a shadow is displaced, in points",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(
                    key: "x", forms: [.number, .variable(.number)], isRequired: true, default: .number(0)
                ),
                PenNestedShape.Field(
                    key: "y", forms: [.number, .variable(.number)], isRequired: true, default: .number(0)
                ),
            ]),
        ]
    )

    // MARK: - Keys more than one effect carries

    /// `enabled` — an effect switched off is kept in the file and not drawn.
    private static let enabledField = PenNestedShape.Field(
        key: "enabled",
        forms: [.boolean, .variable(.boolean)],
        default: .boolean(true)
    )

    /// `radius` — how far a blur reaches, in points.
    private static let radiusField = PenNestedShape.Field(
        key: "radius",
        forms: [.number, .variable(.number)],
        constraint: .length,
        default: .number(0)
    )
}
