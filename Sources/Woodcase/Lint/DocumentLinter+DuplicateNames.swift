//
//  DocumentLinter+DuplicateNames.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/duplicateName`` check.
///
/// Woodcase addresses a node by name, and a name path is a run of consecutive
/// parent→child steps whose **first segment may be any node in the document** — see
/// ``EditableDocument/resolve(_:tags:)-(String,_)``. That is what decides the check's
/// scope, and it decides it narrowly: two nodes sharing a name are separable by a name
/// path as long as they do not share a parent. `Files/TopBar` and `Following/TopBar`
/// each name exactly one node; only the bare `TopBar` is ambiguous, and the ambiguity
/// error already lists both candidates by full path, so the reader is one segment away
/// from the fix. Two nodes sharing a name *and* a parent have no such segment: every
/// path that reaches one reaches the other, however far back it starts. Those are the
/// only duplicates a rename has to fix, and they are what this check reports.
///
/// > Important: this check was document-wide until 2026-09-02, on the argument that
/// > `resolve` matches a bare name anywhere in the file so any shared name is a
/// > latent ambiguity. That argument was wrong — not merely differently scoped. It
/// > read the *bare* name as the only address, when the resolver has always accepted a
/// > longer one, and it cost real work: agents writing files under the wide check
/// > prefixed every node on every board (`Masthead Top Row Title`) to escape it. Short
/// > names, unique among siblings, are the taught style. See
/// > `project/2026-09-02-teach-the-cli-what-it-does.md`.
///
/// Like the `clipped` and `artboard-overlap` checks this is a listing-wide question
/// rather than a per-node one, so it runs once over every row rather than inside
/// ``DocumentLinter/findings(for:parent:in:)``.
///
/// ## Scope
///
/// Siblings are read off the listing itself — the row's parent is the nearest earlier
/// row at a shallower depth — so a document's roots are siblings of one another, and a
/// lint scoped to a subtree judges the rows that subtree puts in the listing. Scope
/// matters far less than it did: siblings are either both in the listing or both out
/// of it, unless the scope root *is* one of them.
extension DocumentLinter {
    /// Findings for every node whose name an earlier sibling in the listing already
    /// holds, keyed by the row each is reported on.
    ///
    /// Unnamed nodes never collide — they are addressed by id, never by a name that
    /// could be shared — so a `nil` ``TreeRow/name`` is skipped entirely.
    ///
    /// Each node after the first occurrence of a name among one parent's children is
    /// reported once, against the first: the row a name path already meant before the
    /// duplicate arrived, and the one a reader fixing the finding keeps. Three
    /// siblings sharing a name are two findings, not three — a full pairwise listing
    /// would repeat the same rename advice once per extra pair for no new information.
    ///
    /// - Parameter rows: The rows of the listing being linted, in pre-order.
    /// - Returns: Row id → the findings to report on that row, in document order.
    static func duplicateNames(rows: [TreeRow]) -> [String: [LintFinding]] {
        var firstBySiblingName: [SiblingName: TreeRow] = [:]
        var byRow: [String: [LintFinding]] = [:]
        var ancestors: [TreeRow] = []

        for row in rows {
            while let last = ancestors.last, last.depth >= row.depth {
                ancestors.removeLast()
            }
            defer { ancestors.append(row) }

            guard let name = row.name else { continue }
            let key = SiblingName(parentID: ancestors.last?.id, name: name)
            guard let first = firstBySiblingName[key] else {
                firstBySiblingName[key] = row
                continue
            }
            byRow[row.id, default: []].append(LintFinding(
                check: .duplicateName,
                nodeID: row.id,
                path: row.address,
                message: "shares the name \"\(name)\" with its sibling \(first.address) "
                    + "(\(first.id)); siblings are the one case no name path separates, because "
                    + "every address that reaches one reaches the other. Rename one, or address "
                    + "either directly by id (`#\(first.id)` / `#\(row.id)`). Two same-named nodes "
                    + "under different parents are fine — an address may start at any node, so one "
                    + "more segment tells those apart."
            ))
        }
        return byRow
    }

    /// A name, within one parent: the identity two nodes have to share to collide.
    ///
    /// `parentID` is `nil` for a row at the top of the listing — the document's roots,
    /// which are siblings of one another under the document itself.
    private struct SiblingName: Hashable {
        let parentID: String?
        let name: String
    }
}
