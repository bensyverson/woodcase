//
//  PenSchema+WoodcaseFields.swift
//  Woodcase
//

import Foundation

/// The `metadata.woodcase` keys an inspector edits as fields of a node, beside its
/// `common.*` and `kind.*` properties.
///
/// A key Woodcase owns in metadata stands in for a property the format lacks — a stroke's
/// dash, since 2.17 (<doc:PenMetadataNamespace>) — so an inspector wants it as one more
/// row: the path it writes, the forms and constraint it keeps to, and what an unset key
/// draws. These rows are not part of ``PenSchema/table(for:)``, which lists the format's
/// own keys; ``PenSchema/field(_:for:)`` finds them by their path.
public extension PenSchema {
    /// The `metadata.woodcase` keys a node of one type takes as fields of its own.
    ///
    /// Every type takes ``PenMetadata/WoodcaseKey/locked``; every type whose stroke the
    /// renderer dashes also takes ``PenMetadata/WoodcaseKey/strokeDash`` and
    /// ``PenMetadata/WoodcaseKey/strokeDashOffset``.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The rows, sorted by path.
    static func woodcaseFields(for type: PenNode.NodeType) -> [PenSchemaTable.Property] {
        var rows = [lockedRow]
        if dashedTypes.contains(type) {
            rows += [strokeDashRow, strokeDashOffsetRow]
        }
        return rows.sorted { $0.path < $1.path }
    }

    // MARK: - Private

    /// The types whose stroke follows one outline the dashes can flow around.
    private static let dashedTypes: Set<PenNode.NodeType> = [.frame, .rectangle, .ellipse, .polygon, .path, .line]

    /// The dash's lengths: none, or an empty list, is solid.
    private static let strokeDashRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.strokeDash.path,
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
        path: PenMetadata.WoodcaseKey.strokeDashOffset.path,
        key: .key(metadataKey(.strokeDashOffset)),
        shape: PenPropertyShape(forms: [.number], example: "2", constraint: PenValueConstraint(unit: .points)),
        default: .number(0)
    )

    /// The lock an editor keeps: unset is unlocked.
    private static let lockedRow = PenSchemaTable.Property(
        path: PenMetadata.WoodcaseKey.locked.path,
        key: .key(metadataKey(.locked)),
        shape: PenPropertyShape(forms: [.boolean], example: "true"),
        default: .boolean(false)
    )

    /// Where the file writes a Woodcase key: `metadata.woodcase.strokeDash`.
    private static func metadataKey(_ key: PenMetadata.WoodcaseKey) -> String {
        "metadata.\(PenMetadata.woodcaseNamespace).\(key.rawValue)"
    }
}
