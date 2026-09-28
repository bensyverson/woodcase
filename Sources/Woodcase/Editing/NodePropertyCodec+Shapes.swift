//
//  NodePropertyCodec+Shapes.swift
//  Woodcase
//

import Foundation

/// The descriptions ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``
/// carries, and the rows `woodcase schema` prints.
///
/// A rejected write is only useful if it says what would have been accepted, so each
/// field name maps to a ``PenPropertyShape``: the forms it takes and a literal to
/// paste. Field names are unique across kinds (`width` is always a sizing, `content`
/// is always a string-or-variable), so one table covers every path.
///
/// **Nothing here spells out a vocabulary by hand.** Every enumerated property is
/// built with ``PenPropertyShape/oneOf(_:)`` from the very type that decodes it, and
/// every structured one points at the key table declared beside its decoder —
/// ``PenFill/schema``, ``PenEffect/schema``, ``PenStrokeWidth/schema`` — because the
/// last time this table described a decoder in its own words it told callers a fill
/// was `{"type":"solid"}` and that a two-element padding was `[horizontal, vertical]`,
/// and both were wrong. `StructuredPropertyShapeTests` writes every
/// ``PenPropertyShape/example`` through the codec so a stale example fails the suite,
/// and `PenSchemaTests` holds every nested table against its payload's own keys.
extension NodePropertyCodec {
    // MARK: - Recurring shapes

    private static let numberOrVariable = PenPropertyShape(forms: [.number, .variable(.number)])
    private static let booleanOrVariable = PenPropertyShape(forms: [.boolean, .variable(.boolean)])
    /// A property whose value is text or a `$variable` reference.
    ///
    /// Internal rather than private because ``NodePropertyCodec/stringFields`` reads
    /// the table for it: a number written to one of these is stored as its string,
    /// and the set of "these" has to be the table's, not a second list.
    static let stringOrVariable = PenPropertyShape(forms: [.text(.plain), .variable(.string)])
    private static let sizing = PenPropertyShape(
        forms: [.number, .spelling("fit_content"), .spelling("fill_container"), .variable(.number)]
    )

    /// A fill or a stroke: the same paint, under two names.
    private static let paint = PenPropertyShape(
        forms: [.text(.color), .variable(.color), .one(PenFill.schema), .eitherInAnArray],
        detail: "a fill object's type is one of \(PenFill.fillTypeNames.joined(separator: ", "))",
        example: ##"[{"type":"color","color":"#FFD166"}]"##
    )

    // MARK: - The table

    /// Field name → the shape a value must have to be accepted.
    static let shapes: [String: PenPropertyShape] = [
        // Common properties
        "name": PenPropertyShape(forms: [.text(.plain)]),
        "x": numberOrVariable,
        "y": numberOrVariable,
        "rotation": numberOrVariable,
        "opacity": numberOrVariable,
        "enabled": booleanOrVariable,
        "flipX": booleanOrVariable,
        "flipY": booleanOrVariable,
        "reusable": PenPropertyShape(forms: [.boolean]),
        "theme": PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(
                phrase: "an object mapping each theme axis to one of its options",
                signature: "{axis: option}"
            ))],
            example: ##"{"mode":"dark"}"##
        ),
        "context": PenPropertyShape(forms: [.text(.plain)]),
        "layoutPosition": PenPropertyShape.oneOf(PenLayoutPosition.self),
        "metadata": PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(
                phrase: "an object with a \"type\" string, which replaces the whole object",
                signature: "{type: string, …}, or one entry at common.metadata.<key>"
            ))],
            detail: "writing common.metadata replaces every key already there; "
                + "common.metadata.<key> merges one entry and leaves the rest, "
                + "so common.metadata._role=button keeps _props",
            example: ##"{"type":"component"}"##
        ),

        // Geometry and layout
        "width": sizing,
        "height": sizing,
        "cornerRadius": PenPropertyShape(
            forms: [.number, .variable(.number), .slots(["topLeft", "topRight", "bottomRight", "bottomLeft"])],
            example: "[8, 8, 0, 0]"
        ),
        "padding": PenPropertyShape(
            forms: [
                .number, .variable(.number),
                .slots(["vertical", "horizontal"]),
                .slots(["top", "right", "bottom", "left"]),
            ],
            example: "[12, 16]"
        ),
        "gap": numberOrVariable,
        "layout": PenPropertyShape.oneOf(PenLayoutDirection.self),
        "justifyContent": PenPropertyShape.oneOf(PenJustifyContent.self),
        "alignItems": PenPropertyShape.oneOf(PenAlignItems.self),
        "clip": booleanOrVariable,
        "slot": PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(phrase: "an array of strings", signature: "[string, …]"))],
            example: ##"["content"]"##
        ),
        "innerRadius": numberOrVariable,
        "startAngle": numberOrVariable,
        "sweepAngle": numberOrVariable,
        "polygonCount": numberOrVariable,
        "geometry": PenPropertyShape(forms: [.text(.svgPathData)], example: ##""M0 0 L10 10""##),
        "viewBox": PenPropertyShape(forms: [.slots(["x", "y", "width", "height"])], example: "[0, 0, 24, 24]"),
        "fillRule": PenPropertyShape.oneOf(PenFillRule.self),

        // Paint
        "fills": paint,
        "stroke": paint,
        "strokeWidth": PenPropertyShape(
            forms: [.number, .variable(.number), .one(PenStrokeWidth.schema)],
            example: ##"{"top":1,"right":1,"bottom":2,"left":1}"##
        ),
        "strokeLinecap": PenPropertyShape.oneOf(PenStrokeCap.self),
        "strokeLinejoin": PenPropertyShape.oneOf(PenStrokeJoin.self),
        "strokeAlignment": PenPropertyShape.oneOf(PenStrokeAlign.self),
        "effects": PenPropertyShape(
            forms: [.one(PenEffect.schema), .many(PenEffect.schema)],
            detail: "an effect object's type is one of \(PenEffect.effectTypeNames.joined(separator: ", "))",
            example: ##"[{"type":"shadow","blur":8,"color":"#00000033"}]"##
        ),
        // Any string decodes: PenBlendMode keeps a mode it does not know rather than
        // refusing it, so this shape names examples and cannot drift out of true.
        "blendMode": PenPropertyShape(
            forms: [.text(.blendMode)],
            detail: "such as normal or multiply; a mode Woodcase does not know is kept as written"
        ),

        // Text
        "content": stringOrVariable,
        "textGrowth": PenPropertyShape.oneOf(PenTextGrowth.self),
        "fontFamily": stringOrVariable,
        "fontSize": numberOrVariable,
        "fontWeight": stringOrVariable,
        "fontStyle": stringOrVariable,
        "letterSpacing": numberOrVariable,
        // The one number in the format that is not points. A reader who assumes the
        // house unit writes 23 for a 15pt face and gets a 345pt line box, silently —
        // so the fact rides on the shape, where a refusal and the schema both see it.
        "lineHeight": PenPropertyShape(
            forms: [.number, .variable(.number)],
            detail: "a multiple of fontSize, not points",
            example: "1.4"
        ),
        "textAlign": PenPropertyShape.oneOf(PenTextAlign.self),
        "textAlignVertical": PenPropertyShape.oneOf(PenTextAlignVertical.self),
        "underline": booleanOrVariable,
        "strikethrough": booleanOrVariable,
        "href": PenPropertyShape(forms: [.text(.plain)]),

        // Components, icons, scripts, prompts
        "ref": PenPropertyShape(forms: [.text(.plain)]),
        "descendants": PenPropertyShape(forms: [.open(PenValueForm.OpenShape(
            phrase: "an object mapping a descendant id to its overrides",
            signature: "{id: {key: value}}"
        ))]),
        "rootOverrides": PenPropertyShape(forms: [.open(PenValueForm.OpenShape(
            phrase: "an object of property overrides",
            signature: "{key: value}"
        ))]),
        "icon": stringOrVariable,
        "library": stringOrVariable,
        "weight": numberOrVariable,
        "model": PenPropertyShape(forms: [.text(.plain)]),
        "scriptUri": PenPropertyShape(forms: [.text(.plain)]),
        "inputs": PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(
                phrase: "an object of numbers, strings, booleans, or $variable references",
                signature: "{key: number | string | boolean | $var}"
            ))],
            example: ##"{"count":3}"##
        ),

        // Browsers. the 2.19 format takes plain values here, never a $variable.
        "url": PenPropertyShape(
            forms: [.text(.plain)],
            detail: "Pen stores it without https://, so example.com means https://example.com",
            example: ##""example.com""##
        ),
        "deviceId": PenPropertyShape(forms: [.text(.plain)]),
        "zoom": PenPropertyShape(forms: [.number], detail: "absent means 1", example: "1.5"),
        "scrollX": PenPropertyShape(forms: [.number]),
        "scrollY": PenPropertyShape(forms: [.number]),

        // Connections.
        "source": PenPropertyShape(
            forms: [.one(PenNode.ConnectionData.endpointSchema)],
            example: ##"{"path":"Card1","anchor":"right"}"##
        ),
        "target": PenPropertyShape(
            forms: [.one(PenNode.ConnectionData.endpointSchema)],
            example: ##"{"path":"Card2","anchor":"left"}"##
        ),
    ]

    // MARK: - Reading the table

    /// The .pen wire shape a property accepts.
    ///
    /// - Parameter field: A property path's field name — the part after `common.`
    ///   or `kind.`, such as `"fills"`.
    /// - Returns: The shape, or `nil` for a field with no described shape.
    public static func shape(of field: String) -> PenPropertyShape? {
        shapes[field]
    }

    /// The shape a value at this field must have, phrased for a person.
    static func expectedShape(of field: String) -> String {
        shape(of: field)?.prose ?? "a valid \(field) value"
    }

    /// The shape a supplied value actually has, and what in it was refused.
    ///
    /// A structured value earns a clause locating the fault, because "an array" is
    /// both an accepted form and, when one element is wrong, the value refused. A
    /// scalar does not: its JSON type against the expected forms is the whole story.
    ///
    /// - Parameters:
    ///   - value: The value that was written.
    ///   - field: The property's field name, for locating the fault inside it.
    ///   - failure: The error the decode raised, if one is at hand.
    /// - Returns: A phrase like `an array ([0].type: "solid" is not an accepted spelling)`.
    static func actualShape(of value: AnyCodable, field: String, failure: Error?) -> String {
        let base = jsonKindName(of: value)
        guard isStructured(value), let failure,
              let clause = PenDecodingFailure.clause(for: failure, field: field)
        else { return base }
        return "\(base) (\(clause))"
    }

    // MARK: - Private

    /// The JSON type a value has, named as a sentence would name it.
    private static func jsonKindName(of value: AnyCodable) -> String {
        switch value {
        case .null: "null"
        case .bool: "a boolean"
        case .int, .double: "a number"
        case .string: "a string"
        case .array: "an array"
        case .dictionary: "an object"
        }
    }

    /// Whether a value has an inside for a refusal to point at.
    private static func isStructured(_ value: AnyCodable) -> Bool {
        switch value {
        case .array, .dictionary: true
        default: false
        }
    }
}
