//
//  RootOverlap+Introduced.swift
//  Woodcase
//

import Foundation

/// The before-and-after that says which overlaps a write *created*.
///
/// Only pairs a write created are worth reporting. An overlap that was already in the
/// file is `lint`'s business; repeating it on every unrelated edit would train a caller
/// to ignore the line. That is why the check is a snapshot taken before the edit and a
/// comparison after it — and why it lives here, beside the geometry it compares, rather
/// than in the verb that first needed it: `woodcase js` is not the only thing that
/// writes, and a script host or an editor warns about exactly the same fact.
public extension RootOverlap {
    /// The overlapping pairs a document has right now.
    ///
    /// - Parameter document: The document, as it stands.
    /// - Returns: The id pairs, order-independent, for comparing against a later state.
    static func pairs(in document: EditableDocument) -> Set<Pair> {
        Set(overlaps(in: document).map(\.pair))
    }

    /// Every overlap that was not there before.
    ///
    /// The comparison is on identity alone — a ``RootOverlap/Pair`` is two ids — because
    /// rects change on both sides of an edit. A write that breaks the layout and a later
    /// one that repairs it net out to nothing, which is why one snapshot bounds a whole
    /// transaction rather than each write inside it.
    ///
    /// - Parameters:
    ///   - before: The pairs ``pairs(in:)`` returned before the edit.
    ///   - document: The document after the edit.
    /// - Returns: One overlap per newly overlapping pair, in document order.
    static func introduced(
        since before: Set<Pair>,
        in document: EditableDocument
    ) -> [RootOverlap] {
        overlaps(in: document).filter { !before.contains($0.pair) }
    }

    /// The overlap as the finding `lint` reports for the same fact.
    ///
    /// One shape for both surfaces: a caller that prints it renders it with
    /// ``LintFormatter``, and gets the line `woodcase lint` prints for the same pair.
    ///
    /// - Parameters:
    ///   - document: The document the overlap was found in, for the node's name path.
    ///   - file: The .pen file to name in the suggested command. A caller with no file at
    ///     hand passes ``RemedyDialect/file``'s placeholder.
    /// - Returns: The finding, about the later of the two roots — the one a remedy moves.
    func finding(in document: EditableDocument, file: String) -> LintFinding {
        LintFinding(
            check: .artboardOverlap,
            nodeID: later.id,
            path: document.namePath(of: later.id),
            message: message(file: file)
        )
    }
}
