//
//  PenEffect+Schema.swift
//  Woodcase
//

import Foundation

/// The key table an `effect` value takes, declared beside the decoder that reads it.
///
/// The spelling an agent gets wrong here is `background_blur` — a blur *behind* a node
/// is not `backdrop`, and the only defense against inventing a name is printing the
/// four the decoder takes. `PenSchemaTests` checks each variant's keys against the
/// payload's own stored properties with `Mirror` — all but a shadow's ``spreadField``,
/// which the codec keeps in metadata.
public extension PenEffect {
    /// An effect object, in every spelling its `type` key takes.
    static let schema = PenNestedShape(
        name: "effect",
        singular: "an effect object",
        plural: "an array of effect objects",
        summary: "a blur, a blur of what is behind the node, a shadow, or a shader run over the drawn node",
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
                    spreadField,
                ]
            ),
            PenNestedShape.Variant(
                spelling: "shader",
                fields: [
                    // No renderer runs a shader, so nothing pins `enabled`'s default here;
                    // it is left unstated, as on the shader fill.
                    enabledField.withoutDefault,
                    PenNestedShape.Field(key: "url", forms: [.text(.plain)], isRequired: true),
                    PenShaderUniform.schemaField,
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

    /// `spread` — how far a shadow is grown before it is cast, in points; negative shrinks
    /// it. The one key of this table the payload does not hold: format 2.19 dropped it, so
    /// the codec stores it in the node's `metadata.woodcase.shadowSpread` and reads it back
    /// onto the shadow (``NodePropertyCodec/presentedValue(at:of:)``). It lists no default:
    /// a file's own shadow cannot carry one, so no renderer reads it there; unset is no spread.
    static let spreadField = PenNestedShape.Field(
        key: NodePropertyCodec.spreadField,
        forms: [.number],
        constraint: PenValueConstraint(unit: .points)
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
