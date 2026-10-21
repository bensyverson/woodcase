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
/// which ``PenSchema/table(for:)`` and ``PenSchema/common`` list with the same row. A
/// shadow's spread is a field of the shadow in `kind.effects` instead (``PenEffect/spreadField``).
/// ``PenSchema/field(_:for:)`` finds every row by its path.
public extension PenSchema {
    /// The `metadata.woodcase` keys a node of one type takes as fields of its own.
    ///
    /// Each key with a row is listed on the types that take its natural path
    /// (``PenMetadata/WoodcaseKey/naturalPathTypes``): ``PenMetadata/WoodcaseKey/locked`` on
    /// every type, ``PenMetadata/WoodcaseKey/defaultTextStyle`` and
    /// ``PenMetadata/WoodcaseKey/spans`` on a text, the dash on every type whose stroke the
    /// renderer dashes and the miter limit on each of those but a line. A shadow's spread
    /// has no row: it is a `spread` field of each shadow in `kind.effects`
    /// (``PenEffect/spreadField``).
    ///
    /// - Parameter type: The node type.
    /// - Returns: The rows, sorted by path.
    static func woodcaseFields(for type: PenNode.NodeType) -> [PenSchemaTable.Property] {
        PenMetadata.WoodcaseKey.allCases.compactMap { key in
            key.naturalPathTypes.contains(type) ? woodcaseRow(for: key) : nil
        }
        .sorted { $0.path < $1.path }
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
        case .props: codegenPropsRow
        case .role: codegenRoleRow
        case .states: codegenStatesRow
        case .action: codegenActionRow
        case .scroll: codegenScrollRow
        default: noteRow(for: key)
        }
    }

    // MARK: - Code generation

    /// A component's published parameters.
    private static let codegenPropsRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.props.propertyPath,
        key: .key(metadataKey(.props)),
        shape: PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(phrase: "a parameters object", signature: "{name: name path}"))],
            detail: "each parameter's name to the name path of the descendant it sets; write one with "
                + "codegen.props.<name>=<name path>",
            example: #"{"label": "Body/Title"}"#
        )
    )

    /// The role a node plays in generated code.
    private static let codegenRoleRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.role.propertyPath,
        key: .key(metadataKey(.role)),
        shape: PenPropertyShape(
            forms: [.text(.plain)],
            detail: "on a component's root, one of \(ComponentRole.allCases.map(\.rawValue).joined(separator: ", ")); "
                + "lint reports any other",
            example: #""button""#
        )
    )

    /// A component's state variants.
    private static let codegenStatesRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.states.propertyPath,
        key: .key(metadataKey(.states)),
        shape: PenPropertyShape(
            forms: [.open(PenValueForm.OpenShape(phrase: "a states object", signature: "{state: node id}"))],
            detail: "each state's name to the id of the node drawing that variant; write one with "
                + "codegen.states.<state>=<node id>",
            example: #"{"hover": "Btn02"}"#
        )
    )

    /// The action an interactive node fires.
    private static let codegenActionRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.action.propertyPath,
        key: .key(metadataKey(.action)),
        shape: PenPropertyShape(forms: [.text(.plain)], detail: "a name for what the node does", example: #""submit""#)
    )

    /// The axis a clipping frame scrolls along.
    private static let codegenScrollRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.scroll.propertyPath,
        key: .key(metadataKey(.scroll)),
        shape: PenPropertyShape(
            forms: [.spelling("vertical"), .spelling("horizontal")],
            detail: "on a clipping frame; lint reports any other value",
            example: #""vertical""#
        )
    )

    // MARK: - Private

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
