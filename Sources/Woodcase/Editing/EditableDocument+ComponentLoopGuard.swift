//
//  EditableDocument+ComponentLoopGuard.swift
//  Woodcase
//

import Foundation

/// The guard that refuses an edit closing a component loop (``ComponentLoop``).
///
/// Every validator of an operation that can add an edge to the component graph — an
/// insert, a move, a replace, a property patch, a retype, a root or descendant override —
/// ends by asking ``refuseComponentLoops(closedBy:)``. The check reads the graph as it
/// would stand after the edit, through a ``ComponentGraphEdit`` overlay, and refuses the
/// edit when some component the edit writes into would gain a component that renders it
/// back. Only edges the edit adds are followed, and an edge between two members of one
/// loop the document already holds closes nothing new, so a document that arrived with a
/// loop still takes every edit that closes no *new* one — the fix among them, and a
/// detach inside the loop.
///
/// The cost is paid only by edits that place an instance, a component or override
/// content naming one, and it is a walk of the components the new edge reaches; a nudge
/// or a rename never reads the graph.
extension EditableDocument {
    /// Runs `body` with the loop guard off, then puts it back as it was.
    ///
    /// For replaying operations whose end state is settled — a session's undo, redo and
    /// rollback return to states the document held, and a merge's operations, checked as
    /// a whole by ``DocumentMerge``, may pass through a loop between two of them.
    ///
    /// - Parameter body: The operations to replay.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `body` throws.
    func allowingComponentLoops<T>(_ body: () throws -> T) rethrows -> T {
        let previous = _componentLoopPolicy
        _componentLoopPolicy = .allow
        defer { _componentLoopPolicy = previous }
        return try body()
    }

    /// Refuses an operation that would close a component loop.
    ///
    /// - Parameter operation: The operation about to be applied, already otherwise valid.
    /// - Throws: ``EditingError/wouldCloseComponentLoop(path:)``, naming the loop.
    func refuseComponentLoops(closedBy operation: EditOperation) throws {
        guard _componentLoopPolicy == .refuse, let edit = componentGraphEdit(for: operation),
              let path = loopClosed(by: edit)
        else { return }
        throw EditingError.wouldCloseComponentLoop(path: path)
    }

    /// The loop an edit would close, as a closed path of component ids, or `nil`.
    ///
    /// - Parameter edit: The edit's overlay.
    /// - Returns: The component written into, the one it would newly render, each one
    ///   after that, and the first again.
    func loopClosed(by edit: ComponentGraphEdit) -> [String]? {
        let view = ComponentGraphView(document: self, edit: edit)
        let current = ComponentGraphView(document: self, edit: ComponentGraphEdit())
        var memo: [String: [String]] = [:]
        let after: (String) -> [String] = { vertex in
            if let known = memo[vertex] { return known }
            let found = view.targets(of: vertex)
            memo[vertex] = found
            return found
        }
        for source in view.components(atOrAbove: edit.sites) {
            let before = current.isComponent(source) ? Set(current.targets(of: source)) : []
            for target in after(source) where !before.contains(target) {
                let walk = target == source ? [] : ComponentLoopIndex.path(from: target, to: source, targets: after)
                guard let walk, !alreadyLooped(source, target) else { continue }
                return [source] + walk + [source]
            }
        }
        return nil
    }

    /// Whether two components are in one loop already — the same component in a loop, or
    /// two members of one — so a new edge between them closes nothing that was not
    /// closed: detaching an instance inside a loop, say, turns `A → B → A` into `A → A`.
    ///
    /// - Parameters:
    ///   - source: The component the edge leaves.
    ///   - target: The component it reaches.
    private func alreadyLooped(_ source: String, _ target: String) -> Bool {
        let index = componentLoopIndex
        guard let group = index.groupOf[source] else { return false }
        return index.groupOf[target] == group
    }
}
