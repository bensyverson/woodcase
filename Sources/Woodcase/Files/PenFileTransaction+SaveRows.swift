//
//  PenFileTransaction+SaveRows.swift
//  Woodcase
//

import Foundation

extension PenFileTransaction {
    /// The rows an app's save appends, in order: an ``ActivityEvent/Kind/external`` row
    /// when the log did not explain the file the save opened, the rows of the changes
    /// the snapshot includes, and a ``ActivityEvent/Kind/merge`` row when the last of
    /// those does not explain the saved revision.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot being saved.
    ///   - changes: The changes the app has not saved yet.
    ///   - lineage: What the log said about the file the save opened.
    ///   - url: The .pen file.
    /// - Returns: The rows to append.
    static func saveRows(
        for snapshot: DocumentSnapshot,
        changes: [CommittedChange],
        lineage: LogLineage,
        at url: URL
    ) -> [ActivityEvent] {
        let included = changes
            .filter { $0.sequence <= snapshot.sequence }
            .sorted { $0.sequence < $1.sequence }
        // Each row names the file this save writes, not the one the session had when the
        // change was made: a session retargeted to a moved file logs under its new name.
        let file = ActivityEvent.canonicalPath(for: url)
        let logged = included.flatMap(\.activity).map { row in
            var row = row
            row.file = file
            return row
        }
        var rows = [lineage.external(naming: url)].compactMap(\.self) + logged
        let explained = rows.last?.revision ?? lineage.newest?.revision
        // A file with no history explains itself, as it does to a CLI transaction.
        if let explained, explained != snapshot.documentRevision {
            rows.append(mergeRow(for: snapshot, folding: folded(in: included), at: url))
        }
        return rows
    }

    /// The changes after the last one that logged rows: the work the session folded in
    /// that no row of the save explains.
    private static func folded(in included: [CommittedChange]) -> [CommittedChange] {
        guard let lastLogged = included.lastIndex(where: { !$0.activity.isEmpty }) else { return included }
        return Array(included[(lastLogged + 1)...])
    }

    /// The row that explains a saved revision no writer's row reaches.
    ///
    /// Its nodes are every node the folded-in work touched, named as the saved document
    /// has them. Its inverse takes that work back out of the saved document, which is
    /// what lets `undo` judge the session's own rows below it exactly; it is complete
    /// only when every folded-in change is a file merge, whose operations the session
    /// applied itself. A collaborator's operations arrive as CRDT operations with no
    /// inverses, so a row folding any of them carries none, and `undo` judges the rows
    /// below it against the document as it stands — which, having moved on, stops it.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot being saved.
    ///   - folding: The folded-in changes, oldest first.
    ///   - url: The .pen file.
    /// - Returns: The row, under the snapshot's author.
    private static func mergeRow(
        for snapshot: DocumentSnapshot,
        folding: [CommittedChange],
        at url: URL
    ) -> ActivityEvent {
        var nodes: [String] = []
        for change in folding {
            let touched = change.applied.flatMap { ActivityEvent.nodeIDs(touchedBy: $0.forward) }
            for node in touched + change.invalidation.nodes.sorted() where !nodes.contains(node) {
                nodes.append(node)
            }
        }
        let invertible = folding.allSatisfy { $0.origin == .file }
        let inverse = invertible
            ? folding.reversed().flatMap { change in
                change.applied.reversed().flatMap { $0.inverse.map(\.operation) }
            }
            : []
        let saved = EditableDocument(from: snapshot.document)
        return ActivityEvent(
            time: Date(),
            identity: snapshot.author?.name ?? ActivityEvent.unattributed,
            file: url,
            op: .merge,
            nodes: nodes,
            paths: nodes.map(saved.namePath(of:)),
            inverse: inverse,
            forward: folding.flatMap { $0.applied.map(\.forward) },
            revision: snapshot.documentRevision,
            batch: UUID().uuidString
        )
    }
}
