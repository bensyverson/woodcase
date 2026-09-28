//
//  DocumentLinter+Overlap.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/artboardOverlap`` check.
///
/// Every other check asks about one node against its parent. This one asks about the
/// *canvas*: a document's roots are artboards, and two artboards on top of each other
/// hide one another in every view that shows the whole file — the bird's-eye canvas,
/// an export of the document, a reader scrolling it. Nothing in the format says which
/// is on top, so there is no reading of the overlap that is correct.
///
/// It is a warning, not an error: a caller mid-edit may have written coordinates it is
/// about to write again, and refusing the write would be worse than saying so. The same
/// sentence reaches the caller twice — once on the write that made the overlap, from
/// ``RootOverlap/message(file:)``, and once here on every `lint` until it is gone.
///
/// Like the `clipped` check this reads the tree read's own settled rects rather than
/// measuring again, so `lint` and `tree` describe one geometry.
extension DocumentLinter {
    /// Findings for every pair of roots that intersect, keyed by the row each is
    /// reported on.
    ///
    /// Reported on the *later* root of the pair, which is the one the remedy moves and
    /// the one a caller most likely just wrote. Keying by row is what keeps the
    /// findings in document order: the walk adds each row's overlaps as it reaches it.
    ///
    /// A listing with fewer than two roots — a lint scoped to one subtree, or a
    /// document with a single artboard — has no pairs, and so no findings.
    ///
    /// - Parameters:
    ///   - rows: The rows of the listing being linted, in pre-order.
    ///   - document: The document they came from, for the name paths a finding prints.
    /// - Returns: Row id → the findings to report on that row, in document order.
    static func artboardOverlaps(rows: [TreeRow], in document: EditableDocument) -> [String: [LintFinding]] {
        let roots = rows.filter { $0.depth == 0 }.compactMap { row in
            row.rect.map { RootOverlap.Root(id: row.id, name: row.name, rect: $0) }
        }
        guard roots.count > 1 else { return [:] }

        var byRow: [String: [LintFinding]] = [:]
        for overlap in RootOverlap.overlaps(among: roots) {
            byRow[overlap.later.id, default: []].append(LintFinding(
                check: .artboardOverlap,
                nodeID: overlap.later.id,
                path: document.namePath(of: overlap.later.id),
                message: overlap.message(file: "<file>")
            ))
        }
        return byRow
    }
}
