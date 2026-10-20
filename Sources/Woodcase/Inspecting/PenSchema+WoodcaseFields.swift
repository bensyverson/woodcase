//
//  PenSchema+WoodcaseFields.swift
//  Woodcase
//

import Foundation

/// The `metadata.woodcase` keys an inspector edits as fields of a node, beside its
/// `common.*` and `kind.*` properties.
///
/// A key Woodcase owns in metadata stands in for a property the format lacks — a stroke's
/// dash and miter limit, since 2.17, and a shadow's spread, since 2.19
/// (<doc:PenMetadataNamespace>) — so an inspector wants it as one more
/// row: the path it writes, the forms and constraint it keeps to, and what an unset key
/// draws. A row's path is the key's natural path (``PenMetadata/WoodcaseKey/naturalPath``),
/// which ``PenSchema/table(for:)`` and ``PenSchema/common`` list with the same row; a key
/// with none yet (a shadow's spread) keeps its storage path, and only this list has it.
/// ``PenSchema/field(_:for:)`` finds every row by its path.
public extension PenSchema {
    /// The `metadata.woodcase` keys a node of one type takes as fields of its own.
    ///
    /// Each key with a row is listed on the types that take its natural path
    /// (``PenMetadata/WoodcaseKey/naturalPathTypes``): ``PenMetadata/WoodcaseKey/locked`` on
    /// every type, ``PenMetadata/WoodcaseKey/defaultTextStyle`` and
    /// ``PenMetadata/WoodcaseKey/spans`` on a text, the dash on every type whose stroke the
    /// renderer dashes and the miter limit on each of those but a line. Every type that takes
    /// effects also takes ``PenMetadata/WoodcaseKey/shadowSpread``, at its storage path until
    /// it becomes a field of the shadow.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The rows, sorted by path.
    static func woodcaseFields(for type: PenNode.NodeType) -> [PenSchemaTable.Property] {
        var rows = PenMetadata.WoodcaseKey.allCases.compactMap { key in
            key.naturalPathTypes.contains(type) ? woodcaseRow(for: key) : nil
        }
        if shadowedTypes.contains(type) { rows.append(shadowSpreadRow) }
        return rows.sorted { $0.path < $1.path }
    }

    /// The row of a key read and written at its natural path, or `nil` for a key the
    /// format's own vocabulary describes (`kind.blendMode`, whose shape is the paint
    /// blend's) or that has no natural path.
    ///
    /// - Parameter key: The Woodcase key.
    /// - Returns: The row, at the key's natural path.
    internal static func woodcaseRow(for key: PenMetadata.WoodcaseKey) -> PenSchemaTable.Property? {
        switch key {
        case .locked: lockedRow
        case .defaultTextStyle: defaultTextStyleRow
        case .spans: spansRow
        case .strokeDash: strokeDashRow
        case .strokeDashOffset: strokeDashOffsetRow
        case .strokeMiterLimit: strokeMiterLimitRow
        default: nil
        }
    }

    // MARK: - Private

    /// The types that take effects, and so shadows.
    private static let shadowedTypes: Set<PenNode.NodeType> = [
        .frame, .rectangle, .ellipse, .polygon, .path, .line, .group, .text, .icon, .browser,
    ]

    /// The miter limit: absent is Pen's 4.
    private static let strokeMiterLimitRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.strokeMiterLimit.propertyPath,
        key: .key(metadataKey(.strokeMiterLimit)),
        shape: PenPropertyShape(
            forms: [.number],
            detail: "the longest a mitered join reaches, in stroke widths, before it is beveled",
            example: "10",
            constraint: PenNode.miterLimitConstraint
        ),
        default: .number(PenNode.defaultMiterLimit)
    )

    /// The shadow spreads: none is no spread.
    private static let shadowSpreadRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.shadowSpread.path,
        key: .key(metadataKey(.shadowSpread)),
        shape: PenPropertyShape(
            forms: [.many(shadowSpreadEntry)],
            detail: "one entry per spread shadow; an entry whose shadow no longer matches the effect at its place "
                + "is ignored",
            example: #"[{"effect": 0, "spread": 4, "shadow": {"type": "shadow", "blur": 8}}]"#
        )
    )

    /// One entry of ``PenMetadata/WoodcaseKey/shadowSpread`` (``PenShadowSpread``).
    private static let shadowSpreadEntry = PenNestedShape(
        name: "shadowSpread",
        singular: "a shadow spread object",
        plural: "an array of shadow spread objects",
        summary: "how far one shadow is grown before it is cast, and the shadow it was made for",
        variants: [
            PenNestedShape.Variant(fields: [
                PenNestedShape.Field(key: "effect", forms: [.number], isRequired: true),
                PenNestedShape.Field(
                    key: "spread", forms: [.number], isRequired: true, constraint: PenValueConstraint(unit: .points)
                ),
                PenNestedShape.Field(key: "shadow", forms: [.one(PenEffect.schema)], isRequired: true),
            ]),
        ]
    )

    /// The dash's lengths: none, or an empty list, is solid.
    private static let strokeDashRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.strokeDash.propertyPath,
        key: .key(metadataKey(.strokeDash)),
        shape: PenPropertyShape(
            forms: [.arrayOf([.number])],
            detail: "alternating dash and gap lengths, at most \(PenStrokeDash.maximumLengths), not all zero; "
                + "absent or empty is solid",
            example: "[8, 4]",
            constraint: .length
        ),
        default: .numbers([])
    )

    /// The dash's phase.
    private static let strokeDashOffsetRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.strokeDashOffset.propertyPath,
        key: .key(metadataKey(.strokeDashOffset)),
        shape: PenPropertyShape(forms: [.number], example: "2", constraint: PenValueConstraint(unit: .points)),
        default: .number(0)
    )

    /// The lock an editor keeps: unset is unlocked.
    private static let lockedRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.locked.propertyPath,
        key: .key(metadataKey(.locked)),
        shape: PenPropertyShape(forms: [.boolean], example: "true"),
        default: .boolean(false)
    )

    /// The mark that makes a text the document's default text style: unset is not the
    /// default.
    private static let defaultTextStyleRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.defaultTextStyle.propertyPath,
        key: .key(metadataKey(.defaultTextStyle)),
        shape: PenPropertyShape(
            forms: [.boolean],
            detail: "the first marked text in document order is the default an editor styles new text like",
            example: "true"
        ),
        default: .boolean(false)
    )

    /// A text's rich text: none is plain.
    private static let spansRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.spans.propertyPath,
        key: .key(metadataKey(.spans)),
        shape: PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(phrase: "a spans object", signature: "{text, runs}"))],
            detail: "the text the runs were made for, and runs of start up to end in UTF-16 units, each setting "
                + "fontFamily, fontSize, fontWeight, fontStyle, fill, underline or strikethrough; "
                + "runs made for other text are ignored",
            example: #"{"text": "Make this bold", "runs": [{"start": 10, "end": 14, "fontWeight": "700"}]}"#
        )
    )

    /// Where the file writes a Woodcase key: `metadata.woodcase.strokeDash`.
    private static func metadataKey(_ key: PenMetadata.WoodcaseKey) -> String {
        "metadata.\(PenMetadata.woodcaseNamespace).\(key.rawValue)"
    }
}
