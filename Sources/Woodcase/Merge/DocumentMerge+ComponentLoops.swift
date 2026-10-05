//
//  DocumentMerge+ComponentLoops.swift
//  Woodcase
//

import Foundation

/// The merge rule for component loops: when the two sides together would make components
/// contain each other (``ComponentLoop``), the local side is kept and the external change
/// that closes the loop is left out and reported as a
/// ``MergeConflict/Kind/wouldCloseComponentLoop``.
///
/// A side alone never holds a new loop — an edit that closes one is refused — but two
/// sides can each add half of one. The merge is resolved as usual, its operations
/// replayed on a copy of the local document, and that copy's loops compared with the
/// local document's. For each new loop, one edge the local side does not have is traced
/// to the external change that made it — an insert, a move, or a rewrite of a `ref`, its
/// overrides or a `reusable` flag — and that change is undone in a copy of the external
/// document, back to the base, before the merge runs again. Only loops the local
/// document did not already hold count, so a file that arrived with one merges as before.
extension DocumentMerge {
    /// The most external changes one merge leaves out for loops before it gives up and
    /// returns what it has; each pass leaves one out.
    private static let loopPassLimit = 64

    /// Merges, leaving out the external changes that would close a component loop.
    ///
    /// - Parameters:
    ///   - base: The common ancestor.
    ///   - ours: The local side.
    ///   - theirs: The external side.
    ///   - merge: One plain merge of the three.
    /// - Returns: The merge, its conflicts joined by one per change left out.
    static func keepingComponentLoopsOut(
        base: EditableDocument,
        ours: EditableDocument,
        theirs: EditableDocument,
        merge: (EditableDocument) -> MergeResult
    ) -> MergeResult {
        var external = theirs
        var left: [MergeConflict] = []
        var result = merge(external)
        for _ in 0 ..< loopPassLimit {
            guard let merged = replay(result.operations, on: ours),
                  let edge = newLoopEdge(in: merged, comparedWith: ours),
                  let (reverted, conflict) = leaveOut(edge, merged: merged, base: base, ours: ours, theirs: external)
            else { break }
            external = reverted
            left.append(conflict)
            result = merge(external)
        }
        result.conflicts += left
        // A change of theirs left out is a difference from the file, whatever the last
        // pass compared against.
        if !left.isEmpty { result.keepsLocalChanges = true }
        return result
    }

    /// The document a merge's operations make of the local one, or `nil` when one of
    /// them does not apply — or when none can add a component edge, which is nearly every
    /// merge, and the loop rule then costs nothing.
    private static func replay(_ operations: [EditOperation], on ours: EditableDocument) -> EditableDocument? {
        guard addsComponentEdge(operations, to: ours) else { return nil }
        let merged = EditableDocument(from: ours.materialize())
        do {
            try merged.allowingComponentLoops {
                for operation in operations {
                    try merged.apply(operation)
                }
            }
        } catch {
            return nil
        }
        return merged
    }

    /// Whether any of a merge's operations could add an edge to the component graph.
    ///
    /// - Parameters:
    ///   - operations: The merge's operations, in order.
    ///   - ours: The local document they apply to.
    /// - Returns: `false` when the merge cannot close a component loop.
    static func addsComponentEdge(_ operations: [EditOperation], to ours: EditableDocument) -> Bool {
        operations.contains(where: ours.canAddComponentEdge)
    }

    /// An edge of the merged graph that closes a loop the local document does not hold.
    ///
    /// - Returns: The component the edge leaves and the one it reaches, or `nil`.
    private static func newLoopEdge(
        in merged: EditableDocument,
        comparedWith ours: EditableDocument
    ) -> (source: String, target: String)? {
        let after = merged.componentLoopIndex
        guard after.hasLoops else { return nil }
        let before = ours.componentLoopIndex
        for (source, targets) in after.edges.sorted(by: { $0.key < $1.key }) {
            guard let group = after.groupOf[source] else { continue }
            let local = Set(before.edges[source] ?? [])
            for target in targets where after.groupOf[target] == group && !local.contains(target) {
                let looped = before.groupOf[source].map { before.groupOf[target] == $0 } ?? false
                if !looped { return (source, target) }
            }
        }
        return nil
    }

    /// Undoes, in a copy of the external document, the change that made one edge, and
    /// says what was left out.
    ///
    /// The edge's ends are checked first — a component the external side made — then
    /// each node from the `ref` that renders the target up to the source: the first one
    /// the merge holds differently from the local side is the external change.
    ///
    /// - Returns: The external document without that change, and the conflict; `nil`
    ///   when no external change explains the edge.
    private static func leaveOut(
        _ edge: (source: String, target: String),
        merged: EditableDocument,
        base: EditableDocument,
        ours: EditableDocument,
        theirs: EditableDocument
    ) -> (EditableDocument, MergeConflict)? {
        var candidates = [edge.target, edge.source].filter { ours.componentRegistry[$0] == nil }
        if candidates.isEmpty, let witness = renderingRef(of: edge.target, in: edge.source, merged: merged) {
            var cursor: String? = witness
            while let id = cursor {
                candidates.append(id)
                if id == edge.source { break }
                cursor = merged.parents[id]
            }
        }
        for id in candidates {
            if let reverted = ComponentLoopRevert(id: id, merged: merged, base: base, ours: ours, theirs: theirs).run() {
                return reverted
            }
        }
        return nil
    }

    /// A node in a component's subtree that renders the target, nearest the top first.
    private static func renderingRef(of target: String, in component: String, merged: EditableDocument) -> String? {
        var pending = [component]
        while !pending.isEmpty {
            let id = pending.removeFirst()
            if let node = merged.nodes[id], node.renderedComponentIDs.contains(target) { return id }
            pending += merged.children[id] ?? []
        }
        return nil
    }
}
