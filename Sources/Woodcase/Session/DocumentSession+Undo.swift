//
//  DocumentSession+Undo.swift
//  Woodcase
//

import Foundation

public extension DocumentSession {
    /// Whether ``SessionOrigin/undo`` has an entry to take back.
    var canUndo: Bool {
        !history.undo.isEmpty
    }

    /// Whether ``SessionOrigin/redo`` has an entry to put back.
    var canRedo: Bool {
        !history.redo.isEmpty
    }
}

extension DocumentSession {
    /// Which stack an undo or a redo takes its entry from.
    enum HistoryDirection: Friendly {
        /// Take back the most recent undo entry; its reversal joins redo.
        case undo
        /// Put back the most recently undone entry; its reversal joins undo.
        case redo
    }

    /// Takes back the author's most recent undo entry, or puts back the most recently
    /// undone one, keeping every other author's later work.
    ///
    /// Each reversal of the entry is weighed against the ledger before it runs
    /// (``objections(to:since:)``): a step another author has since written over is
    /// left as they wrote it and reported in ``CommittedChange/kept``, a step stopped by
    /// a node gone or an id taken that nobody else is to credit for is reported in
    /// ``CommittedChange/unrestored`` — a step never goes untaken silently — and a
    /// reversal that adds, removes, moves or rebuilds nodes is skipped whole when any of
    /// its steps is, its steps weighed in order. What does run goes through the same path as a local edit — through the
    /// CRDT, into the activity log — and its inverses become the entry for the opposite
    /// stack. The whole undo lands or none of it does.
    ///
    /// - Parameter direction: Undo or redo.
    /// - Returns: The change. With nothing to take back, or nothing left once others'
    ///   work is kept, it applies nothing and keeps the current sequence.
    /// - Throws: The ``EditingError`` of a step that failed; the session is left as it was.
    func commitHistory(_ direction: HistoryDirection) throws -> CommittedChange {
        let origin: SessionOrigin.Kind = direction == .undo ? .undo : .redo
        guard let entry = direction == .undo ? history.undo.last : history.redo.last else {
            return emptyChange(origin: origin)
        }

        let crdtBefore = document.crdtDocument?.snapshot()
        var pending = pendingChange(activityKind: direction == .undo ? .undo : .redo)
        var objected: [Objection] = []
        var reversals: [UndoEntry.Reversal] = []
        do {
            // A history step returns to a state the document held, so it is never
            // refused for a component loop: undoing a loop's fix puts the loop back.
            try document.allowingComponentLoops {
                for reversal in entry.reversals {
                    let start = pending.applied.count
                    try objected.append(apply(reversal, since: entry.sequence, into: &pending))
                    let applied = pending.applied[start...]
                    if !applied.isEmpty {
                        reversals.insert(UndoEntry.Reversal(steps: applied.reversed().flatMap(\.inverse)), at: 0)
                    }
                }
            }
        } catch {
            abandon(pending, restoring: crdtBefore)
            throw error
        }

        switch direction {
        case .undo: history.undo.removeLast()
        case .redo: history.redo.removeLast()
        }
        history.openGroup = nil
        let objection = Objection.merged(objected)
        guard !pending.applied.isEmpty else {
            var change = emptyChange(origin: origin, kept: objection.kept, undoEffect: .consumedEntry)
            change.unrestored = objection.unrestored
            return change
        }

        var change = commit(pending, origin: origin, isUndoable: direction == .redo, kept: objection.kept)
        change.unrestored = objection.unrestored
        change.undoEffect = [.consumedEntry, .filedReversal]
        let opposite = UndoEntry(sequence: change.sequence, reversals: reversals)
        switch direction {
        case .undo: history.redo.append(opposite)
        case .redo: history.undo.append(opposite)
        }
        return change
    }

    /// Applies what can be applied of one reversal.
    ///
    /// - Parameters:
    ///   - reversal: The steps that take back one operation.
    ///   - sequence: The entry's sequence; only writes after it can be someone's to keep.
    ///   - pending: The change the steps join.
    /// - Returns: What stopped the steps that did not run: other authors' work left in
    ///   place, and what nobody is to credit for.
    /// - Throws: The ``EditingError`` of a step that failed.
    private func apply(
        _ reversal: UndoEntry.Reversal,
        since sequence: UInt64,
        into pending: inout PendingChange
    ) throws -> Objection {
        if reversal.steps.contains(where: \.isStructural) {
            // Weighed in step order: a later step's guard may name a node an earlier step
            // of this same reversal puts back — a detach's connector restores name the
            // ref its re-insert recreates.
            var scope = ReversalScope()
            var objected: [Objection] = []
            for step in reversal.steps {
                if let objection = objections(to: step, since: sequence, scope: scope) {
                    objected.append(objection)
                }
                scope.advance(past: step.operation, in: document)
            }
            guard objected.isEmpty else { return Objection.merged(objected) }
            for step in reversal.steps {
                try apply(step.resolved(in: document), into: &pending)
            }
            return Objection()
        }
        var objected: [Objection] = []
        for step in reversal.steps {
            if let objection = objections(to: step, since: sequence) {
                objected.append(objection)
            } else {
                try apply(step.resolved(in: document), into: &pending)
            }
        }
        return Objection.merged(objected)
    }

    /// Why a step must not run, or `nil` if it may.
    ///
    /// The scope a step is weighed against depends on what it does:
    ///
    /// - Removing or rebuilding a subtree (undoing an insert, a detach or a replace):
    ///   any key of any node in the subtree, the root's place included.
    /// - Moving a node back: the node's place, and that the node and its old parent
    ///   still exist.
    /// - Putting a node back (undoing a delete): that its parent still exists and none
    ///   of its ids has been taken again.
    /// - Anything else: the keys it restores, and that their node still exists.
    ///
    /// A node is weighed with the reversal's earlier steps in mind (`scope`): one they put
    /// back is not missing, and an id they free is not taken. Writes by others are
    /// weighed against the ledger as it stands, so nothing an earlier step does excuses
    /// one.
    ///
    /// - Parameters:
    ///   - step: The step.
    ///   - sequence: The entry's sequence.
    ///   - scope: What the reversal's steps before this one add and remove.
    /// - Returns: What stops the step — other authors' writes, and the nodes gone or ids
    ///   taken that nobody else is to credit for — or `nil` if it may run.
    func objections(
        to step: GuardedInverse,
        since sequence: UInt64,
        scope: ReversalScope = ReversalScope()
    ) -> Objection? {
        let missing = { (id: String) in scope.isMissing(id, in: self.document) }
        switch step.operation {
        case let .deleteNode(op):
            return subtreeObjections(op.nodeID, since: sequence, scope: scope)
        case let .replaceSubtree(op):
            return subtreeObjections(op.node.id, since: sequence, scope: scope)
        case let .detachRef(op):
            return subtreeObjections(op.refNodeID, since: sequence, scope: scope)
        case let .moveNode(op):
            let parentID = step.placement?.parentID ?? op.newParentID
            let missing = [op.nodeID, parentID].compactMap(\.self).filter(missing)
            return objections(
                missing: missing,
                written: [.placement(node: op.nodeID)],
                since: sequence
            )
        case let .insertNode(op):
            let parentID = step.placement?.parentID ?? op.parentID
            let gone = [parentID].compactMap(\.self).filter(missing)
            let taken = document.collectInsertedIDs(in: op.node).filter { scope.isTaken($0, in: document) }
            return objections(
                missing: gone + taken,
                written: [],
                since: sequence
            )
        default:
            let gone = Set(step.keys.compactMap(\.nodeID)).sorted().filter(missing)
            return objections(missing: gone, written: step.keys, since: sequence)
        }
    }

    /// The objections to removing or rebuilding a subtree: every later write by
    /// someone else to a node inside it.
    ///
    /// A subtree an earlier step of the reversal put back is the reversal's own, so no
    /// one else can have written inside it.
    private func subtreeObjections(_ rootID: String, since sequence: UInt64, scope: ReversalScope) -> Objection? {
        guard document.nodes[rootID] != nil else {
            if !scope.isMissing(rootID, in: document) { return nil }
            return objections(missing: [rootID], written: [], since: sequence)
        }
        let subtree = Set(document.descendantIDs(of: rootID))
        let written = ledger.stamps.keys.filter { $0.nodeID.map(subtree.contains) ?? false }
        return objections(missing: [], written: written, since: sequence)
    }

    /// The objections a step meets.
    ///
    /// - Parameters:
    ///   - missing: Nodes the step needs that are gone, or ids it would take that are in
    ///     use. Any one of them stops the step; whoever last wrote its existence, if
    ///     someone else, is credited, and otherwise its existence is reported as
    ///     ``Objection/unrestored``.
    ///   - written: Keys someone else must not have written since the entry.
    ///   - sequence: The entry's sequence.
    /// - Returns: `nil` if nothing stops the step; otherwise the other authors' writes
    ///   that do, in the order they were made, and what no one is to credit for.
    private func objections(missing: [String], written: [ChangeKey], since sequence: UInt64) -> Objection? {
        let contested = written.compactMap { foreignWrite(to: $0, since: sequence) }
        guard !missing.isEmpty || !contested.isEmpty else { return nil }
        var gone: [(kept: KeptChange, sequence: UInt64)] = []
        var unrestored: [ChangeKey] = []
        for id in missing {
            if let write = foreignWrite(to: .existence(node: id), since: 0) {
                gone.append(write)
            } else {
                unrestored.append(.existence(node: id))
            }
        }
        let ordered = (gone + contested).sorted {
            ($0.sequence, String(describing: $0.kept.key)) < ($1.sequence, String(describing: $1.kept.key))
        }
        return Objection(kept: ordered.map(\.kept), unrestored: unrestored).deduplicated
    }

    /// Another author's write to a key after a sequence, if there is one.
    private func foreignWrite(to key: ChangeKey, since sequence: UInt64) -> (kept: KeptChange, sequence: UInt64)? {
        guard let stamp = ledger.stamp(for: key), stamp.author != author, stamp.sequence > sequence else {
            return nil
        }
        return (KeptChange(key: key, author: stamp.author), stamp.sequence)
    }
}
