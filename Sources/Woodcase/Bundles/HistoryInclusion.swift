//
//  HistoryInclusion.swift
//  Woodcase
//

/// Whether a copy of a bundle takes its shared history with it.
///
/// A bundle's `history/` is one append-only file per writer (<doc:WoodcaseActivityLog>).
/// Every way of copying a bundle out — ``PenBundle/copy(_:to:history:)`` and
/// ``PenBundle/export(_:to:identity:history:)`` — asks for this choice explicitly, so no
/// path decides it by accident. Ben's ruling (H5, 2026-10-23): a copy that is the same
/// design going on — Save As, Duplicate — passes ``included``; a copy that leaves the
/// project — Save To, Export — asks the person, and "Export Without History" is
/// ``omitted``.
///
/// Only the writers' files travel. The bundle's own `.gitignore` and its local
/// `.woodcase/` state (views, cursors, temporary files) never do, whichever case is
/// passed: they belong to the folder they sit in, not to the design.
public enum HistoryInclusion: Friendly, CaseIterable {
    /// Copy every writer's live and archived history file.
    case included

    /// Copy none: the copy starts with no history of its own.
    case omitted
}
