//
//  PenFill+Schema.swift
//  Woodcase
//

import Foundation

/// The key table a `fill` or `stroke` value takes, declared beside the decoder that reads it.
///
/// It lives here rather than with the help that prints it for one reason: a key added to
/// ``PenFill/PenColorFill`` and friends should be one screen away from the row that has
/// to describe it. `PenSchemaTests` enforces the rest with `Mirror` — every variant's
/// keys must be the payload's own stored properties.
public extension PenFill {
    /// A fill object, in every spelling its `type` key takes.
    static let schema = PenNestedShape(
        name: "fill",
        singular: "a fill object",
        plural: "an array of fill objects",
        summary: "the paint a fill or stroke key takes; a bare color string is the shorthand",
        discriminator: "type",
        variants: [
            PenNestedShape.Variant(
                spelling: "color",
                fields: [
                    enabledField, blendModeField,
                    PenNestedShape.Field(
                        key: "color",
                        forms: [.text(.color), .variable(.color)],
                        isRequired: true
                    ),
                ]
            ),
            PenNestedShape.Variant(
                spelling: "gradient",
                fields: [
                    enabledField, blendModeField,
                    PenNestedShape.Field(
                        key: "gradientType",
                        forms: PenGradientType.allCases.map { .spelling($0.rawValue) }
                    ),
                    opacityField,
                    PenNestedShape.Field(key: "center", forms: [.one(positionSchema)]),
                    PenNestedShape.Field(key: "size", forms: [.one(sizeSchema)]),
                    PenNestedShape.Field(key: "rotation", forms: [.number, .variable(.number)]),
                    PenNestedShape.Field(key: "colors", forms: [.many(stopSchema)]),
                ]
            ),
            PenNestedShape.Variant(
                spelling: "image",
                fields: [
                    enabledField, blendModeField, opacityField,
                    PenNestedShape.Field(key: "url", forms: [.text(.plain)]),
                    PenNestedShape.Field(
                        key: "mode",
                        forms: PenImageFillMode.allCases.map { .spelling($0.rawString) }
                    ),
                    PenNestedShape.Field(key: "transform", forms: [.slots(PenImageTransform.slotNames)]),
                ]
            ),
            PenNestedShape.Variant(
                spelling: "mesh_gradient",
                fields: [
                    enabledField, blendModeField, opacityField,
                    PenNestedShape.Field(key: "columns", forms: [.number]),
                    PenNestedShape.Field(key: "rows", forms: [.number]),
                    PenNestedShape.Field(
                        key: "colors",
                        forms: [.open(PenValueForm.OpenShape(
                            phrase: "an array of color strings",
                            signature: "[color | $color, …]"
                        ))]
                    ),
                    PenNestedShape.Field(
                        key: "points",
                        forms: [.arrayOf([.slots(["x", "y"]), .one(meshPointSchema)])]
                    ),
                ]
            ),
            PenNestedShape.Variant(
                spelling: "shader",
                fields: [
                    enabledField, blendModeField, opacityField,
                    PenNestedShape.Field(key: "url", forms: [.text(.plain)], isRequired: true),
                    PenNestedShape.Field(
                        key: "uniforms",
                        forms: [.open(PenValueForm.OpenShape(
                            phrase: "an object of uniform names to numbers, colors, booleans or vectors",
                            signature: "{name: number | color | boolean | [number, …] | $var}"
                        ))]
                    ),
                ]
            ),
        ]
    )

    /// One stop of a gradient: a color and where along the ramp it sits.
    static let stopSchema = PenNestedShape(
        name: "gradient stop",
        singular: "a gradient stop",
        plural: "an array of gradient stops",
        summary: "one color of a gradient, and its position from 0 to 1",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "color", forms: [.text(.color), .variable(.color)], isRequired: true),
                PenNestedShape.Field(key: "position", forms: [.number, .variable(.number)], isRequired: true),
            ]),
        ]
    )

    /// One vertex of a mesh gradient, in its object form (``PenMeshPoint/Object``).
    ///
    /// The bare `[x, y]` form sits beside it in the `points` row; the summary says
    /// what an omitted handle becomes, since that is the thing a writer cannot guess.
    static let meshPointSchema = PenNestedShape(
        name: "mesh point",
        singular: "a mesh point object",
        plural: "an array of mesh point objects",
        summary: "one vertex in the node's unit box; handles are offsets, a quarter cell when omitted",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "position", forms: [.slots(["x", "y"])], isRequired: true),
                PenNestedShape.Field(key: "leftHandle", forms: [.slots(["dx", "dy"])]),
                PenNestedShape.Field(key: "rightHandle", forms: [.slots(["dx", "dy"])]),
                PenNestedShape.Field(key: "topHandle", forms: [.slots(["dx", "dy"])]),
                PenNestedShape.Field(key: "bottomHandle", forms: [.slots(["dx", "dy"])]),
            ]),
        ]
    )

    /// Where a gradient is centered, as a fraction of the node's box.
    static let positionSchema = PenNestedShape(
        name: "fill position",
        singular: "a position object",
        plural: "an array of position objects",
        summary: "a point in the node's box, as fractions from 0 to 1",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "x", forms: [.number]),
                PenNestedShape.Field(key: "y", forms: [.number]),
            ]),
        ]
    )

    /// How far a gradient reaches, as a fraction of the node's box.
    static let sizeSchema = PenNestedShape(
        name: "fill size",
        singular: "a size object",
        plural: "an array of size objects",
        summary: "a gradient's reach, as fractions of the node's box",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "width", forms: [.number, .variable(.number)]),
                PenNestedShape.Field(key: "height", forms: [.number, .variable(.number)]),
            ]),
        ]
    )

    // MARK: - Keys every fill variant carries

    /// `enabled` — a fill switched off is kept in the file and not painted.
    private static let enabledField = PenNestedShape.Field(
        key: "enabled",
        forms: [.boolean, .variable(.boolean)]
    )

    /// `blendMode` — how this fill composites onto what is under it.
    private static let blendModeField = PenNestedShape.Field(
        key: "blendMode",
        forms: [.text(.blendMode)]
    )

    /// `opacity` — the fill's own opacity, on top of the node's.
    private static let opacityField = PenNestedShape.Field(
        key: "opacity",
        forms: [.number, .variable(.number)]
    )
}
