//
//  DocumentLinter+NoteUnsized.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/noteUnsized`` check.
///
/// Pen saves a note it was never given a size for as `width: 0, height: 0`, and
/// Woodcase lays such a note out at ``PenPostIt/defaultSize`` on each axis
/// (``PenPostIt/layoutSizing(_:)``), so the 0×0 note draws as a 200×200 post-it. That
/// is right, but it is implicit: Pen itself draws the note at its own idea of a size,
/// and a reader of the file sees zeros. Writing the size makes the file say what it
/// draws, which is all this notice suggests.
extension DocumentLinter {
    /// A note whose width or height is absent or not above zero.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders.
    /// - Returns: Zero or one finding, naming every axis left to the default.
    static func noteUnsized(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case let .note(data) = node.kind else { return [] }
        let axes = [("width", data.width), ("height", data.height)]
            .filter { PenPostIt.isUnsized($0.1) }
            .map(\.0)
        guard !axes.isEmpty else { return [] }

        let size = Int(PenPostIt.defaultSize)
        let unset = axes.map { "kind.\($0)" }.joined(separator: " and ")
        let sets = axes.map { "kind.\($0)=\(size)" }.joined(separator: " ")
        let verb = axes.count > 1 ? "are" : "is"
        return [finding(
            .noteUnsized, row,
            "lays out at the post-it default of \(size)pt because \(unset) \(verb) unset or 0. Run "
                + "`woodcase set <file> \(row.id) \(sets)` to write the size it draws at."
        )]
    }
}
