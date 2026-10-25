//
//  EditableDocument+Remote.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Takes in one remote CRDT operation, applying it — and anything it was holding up —
    /// once its causal past has arrived.
    ///
    /// Delivery is causal and exactly-once (see ``CRDTDocument/heldOperations``): an
    /// operation whose dependencies have not all been applied is held until they have,
    /// and one already applied or held is ignored. What a delivery placed is reconciled
    /// with the CRDT (``reconcileChildrenWithParents(after:)``) afterwards.
    ///
    /// An operation out of range for this replica (``CRDTDocument/validateRemote(_:)``)
    /// is refused before the CRDT records it, and the refusal is returned for the caller
    /// to report.
    ///
    /// - Parameter operation: The remote CRDT operation from another peer.
    /// - Returns: Why the operation was refused at the boundary, or `nil` when it was
    ///   taken (applied, held, or ignored as a duplicate — which includes the CRDT's own
    ///   no-ops, such as a stale write).
    @discardableResult
    func applyRemote(_ operation: CRDTOperation) -> RemoteInputError? {
        applyRemote([operation]).first
    }

    /// Takes in a batch of remote CRDT operations, in any order, applying each once its
    /// causal past has arrived.
    ///
    /// Operations refused at the boundary (``CRDTDocument/validateRemote(_:)``) are
    /// skipped and returned; duplicates are ignored; the rest are applied in causal
    /// order, now or — for those whose causal past is still missing — when a later batch
    /// brings it. The CRDT's own no-ops (a stale write, a cycle-creating move) are
    /// applied as no-ops. A final reconciliation of what the batch placed ensures
    /// structural consistency.
    ///
    /// - Parameter operations: The remote CRDT operations to apply.
    /// - Returns: The refusals, in the order of the operations they refused.
    @discardableResult
    func applyRemote(_ operations: [CRDTOperation]) -> [RemoteInputError] {
        guard let crdtDocument else { return [] }
        var refused: [RemoteInputError] = []
        var journal = FlatStoreJournal()
        var applied = false
        for operation in operations {
            do {
                try receiveRemote(operation)
            } catch {
                refused.append(error)
                continue
            }
            // Drained after each one, so a batch in causal order never holds more than
            // the operation in hand.
            while let next = crdtDocument.nextDeliverable() {
                applied = applyDelivered(next, journal: &journal).isEmpty == false || applied
            }
        }
        if applied {
            reconcileChildrenWithParents(after: &journal)
            onRemoteChange?()
        }
        return refused
    }

    /// Runs one remote operation through the CRDT at once and writes what it accepted
    /// into the flat store, returning the mutations written.
    ///
    /// This is the raw step, without causal delivery: the operation is applied as given,
    /// whether or not its causal past has arrived or it was applied before. It does not
    /// reconcile the children lists with the parents. Use ``applyRemote(_:)-([CRDTOperation])``
    /// to take operations from a peer.
    ///
    /// - Parameter operation: The remote CRDT operation.
    /// - Returns: The mutations written, in order; empty when the CRDT rejected the
    ///   operation (a stale write, a cycle-creating move), when the boundary refused it
    ///   (``CRDTDocument/validateRemote(_:)``), or when the document is not
    ///   collaborative.
    @discardableResult
    func applyRemoteMutations(_ operation: CRDTOperation) -> [DocumentMutation] {
        var journal = FlatStoreJournal()
        return (try? applyRemoteMutations(operation, journal: &journal)) ?? []
    }

    /// Returns CRDT operations not yet seen by the given vector clock.
    ///
    /// Use this to determine which operations to send to a peer that has
    /// the given clock state.
    ///
    /// - Parameter since: The recipient's vector clock state.
    /// - Returns: Operations to send, or an empty array if not in collaborative mode.
    func pendingOperations(since: VectorClock) -> [CRDTOperation] {
        guard let crdtDocument else { return [] }
        return crdtDocument.pendingOperations(since: since)
    }
}

extension EditableDocument {
    /// Checks a remote operation at the boundary and hands it to the CRDT's hold, from
    /// which ``CRDTDocument/nextDeliverable()`` releases it in causal order.
    ///
    /// - Parameter operation: The remote operation.
    /// - Throws: The ``RemoteInputError`` that refused it; nothing was recorded.
    func receiveRemote(_ operation: CRDTOperation) throws(RemoteInputError) {
        guard let crdtDocument else { return }
        try crdtDocument.validateRemote(operation)
        crdtDocument.hold(operation)
    }

    /// Applies one operation ``CRDTDocument/nextDeliverable()`` released, noting every
    /// write in a batch's journal first.
    ///
    /// - Parameters:
    ///   - operation: The released operation.
    ///   - journal: The batch's journal.
    /// - Returns: The mutations written, in order; empty when the CRDT rejected it.
    @discardableResult
    func applyDelivered(_ operation: CRDTOperation, journal: inout FlatStoreJournal) -> [DocumentMutation] {
        guard let crdtDocument,
              let mutations = crdtDocument.processDelivered(operation: operation, document: self)
        else { return [] }
        write(mutations, journal: &journal)
        return mutations
    }

    /// The raw step with a batch's journal: one remote operation through the boundary and
    /// the CRDT at once, without causal delivery.
    ///
    /// Every write is noted before it lands, so the journal names the batch's whole
    /// footprint: what ``reconcileChildrenWithParents(after:)`` settles and what a
    /// ``ChangeInvalidation/RemoteProbe`` compares.
    ///
    /// - Parameters:
    ///   - operation: The remote CRDT operation.
    ///   - journal: The batch's journal.
    /// - Returns: The mutations written, in order; empty when the CRDT rejected the
    ///   operation or the document is not collaborative.
    /// - Throws: The ``RemoteInputError`` that refused the operation at the boundary;
    ///   nothing was recorded or written.
    @discardableResult
    func applyRemoteMutations(
        _ operation: CRDTOperation, journal: inout FlatStoreJournal
    ) throws(RemoteInputError) -> [DocumentMutation] {
        guard let crdtDocument,
              let mutations = try crdtDocument.processValidatedRemote(operation: operation, document: self)
        else { return [] }
        write(mutations, journal: &journal)
        return mutations
    }

    /// Notes each mutation in the journal, then writes it.
    private func write(_ mutations: [DocumentMutation], journal: inout FlatStoreJournal) {
        for mutation in mutations {
            journal.note(mutation, in: self)
            applyMutation(mutation)
        }
    }
}
