//
//  PenSchema+NoteFields.swift
//  Woodcase
//

import Foundation

/// The schema rows of the note keys and a note's text style, at their `note.*` aliases.
///
/// A note, a prompt and a context take each one (``PenMetadata/WoodcaseKey/noteTypes``),
/// so the rows join those types' tables and ``PenSchema/woodcaseFields(for:)``. Each row is
/// read off the key itself — its ``PenMetadata/WoodcaseKey/shape``, ``PenMetadata/WoodcaseKey/spellings``,
/// ``PenMetadata/WoodcaseKey/constraint`` and ``PenMetadata/WoodcaseKey/summary`` — the same
/// vocabulary `woodcase schema postit` and the authoring check use, so the three cannot
/// disagree. The raw storage path is accepted beside the alias (leaf DPY8DH).
extension PenSchema {
    /// The row of a note key at its `note.*` alias, or `nil` for a key that is not one.
    ///
    /// - Parameter key: The Woodcase key.
    /// - Returns: The row, its `.pen key` the storage key.
    static func noteRow(for key: PenMetadata.WoodcaseKey) -> PenSchemaTable.Property? {
        guard key.group == .note || key.group == .noteTextStyle, let path = key.naturalPath else { return nil }
        return PenSchemaTable.Property(
            path: path,
            key: .key("metadata.\(PenMetadata.woodcaseNamespace).\(key.rawValue)"),
            shape: PenPropertyShape(forms: forms(of: key), detail: key.summary, constraint: key.constraint)
        )
    }

    /// The value forms a note key takes, from its shape.
    private static func forms(of key: PenMetadata.WoodcaseKey) -> [PenValueForm] {
        switch key.shape {
        case let .oneOf(spellings): spellings.map(PenValueForm.spelling)
        case .number: [.number]
        case .boolean: [.boolean]
        case .hexColor: [.text(.color)]
        case .string, .utcTimestamp: [.text(.plain)]
        case .any, .textSpans, .dashLengths, .textDecoration, .shadowSpreads:
            [.open(PenValueForm.OpenShape(phrase: "any JSON value", signature: "any"))]
        }
    }
}
