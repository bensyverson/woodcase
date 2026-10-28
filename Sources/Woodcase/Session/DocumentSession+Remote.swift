//
//  DocumentSession+Remote.swift
//  Woodcase
//

import Foundation

public extension DocumentSession {
    /// Introduces a collaborator, so the writes their replica makes are credited to them.
    ///
    /// Each CRDT operation names the replica that made it, not the person; this is
    /// the mapping back. Call it when a peer joins. A ``SessionOrigin/remote(_:from:)``
    /// submission introduces its sender too, so an operation relayed through one peer
    /// on behalf of another is credited to whoever made it, as long as that peer has
    /// been introduced; one from the session's own replica is credited to the session's
    /// author, and one from a replica nobody introduced to
    /// ``Author/unattributed(peer:)``.
    ///
    /// - Parameter author: The collaborator, with the peer id their replica uses.
    func noteJoined(_ author: Author) {
        peers[author.peerID] = author
    }
}

extension DocumentSession {
    /// Applies a collaborator's CRDT operations.
    ///
    /// Operations are delivered causally and exactly once: each is checked at the
    /// boundary and handed to the CRDT's hold, and after each, every held operation whose
    /// causal past has been applied — from this batch or an earlier one — is applied, in
    /// causal order (``CRDTDocument/heldOperations``). One whose causal past is still missing waits
    /// for a later batch; one already applied is ignored.
    ///
    /// Each operation is keyed against the document before it lands
    /// (``ChangeKey/keys(ofRemote:in:)``), then run through the CRDT; only the ones the
    /// CRDT accepts are stamped, under the author of the replica that made them. What
    /// the batch placed is reconciled once, after the last operation, and the
    /// invalidation is read by comparing what the batch wrote with the document after
    /// (``ChangeInvalidation/RemoteProbe``) — both in proportion to the batch, so a
    /// collaborator's one-property change costs a spine, not the document.
    ///
    /// The change is somebody else's work: it joins no undo history — the local
    /// author's undo keeps it instead, through the ledger — leaves redo and the open
    /// undo group as they were, writes no activity (the collaborator's own session
    /// logs it), broadcasts nothing and does not dirty the file.
    ///
    /// - Parameters:
    ///   - operations: The operations, in the order they arrived.
    ///   - sender: The collaborator who sent them, who joins the peer registry; a sender
    ///     on the session's own replica is the session's author, whatever name it carries.
    /// An operation the boundary refuses (``CRDTDocument/validateRemote(_:)``) is skipped
    /// and reported on ``CommittedChange/rejected``; the rest of the batch still lands.
    ///
    /// - Returns: The committed change; with nothing applied — every operation held,
    ///   ignored or refused — an empty change that keeps the current sequence.
    /// - Throws: ``SessionError/notCollaborative`` when the session keeps no CRDT.
    func commitRemote(_ operations: [CRDTOperation], from sender: Author) throws -> CommittedChange {
        guard let crdt = document.crdtDocument else { throw SessionError.notCollaborative }
        let sender = sender.peerID == author.peerID ? author : sender
        noteJoined(sender)

        var probe = ChangeInvalidation.RemoteProbe(document)
        var mutations: [DocumentMutation] = []
        var writes: [(keys: [ChangeKey], author: Author)] = []
        var rejected: [RemoteInputError] = []
        for operation in operations {
            do {
                try document.receiveRemote(operation)
            } catch {
                rejected.append(error)
                continue
            }
            // Drained after each one, so a batch in causal order never holds more than
            // the operation in hand.
            while let delivered = crdt.nextDeliverable() {
                let keys = ChangeKey.keys(ofRemote: delivered, in: document)
                let applied = document.applyDelivered(delivered, journal: &probe.journal)
                guard !applied.isEmpty else { continue }
                mutations += applied
                writes.append((keys, author(of: delivered.id.peerID)))
            }
        }
        guard !mutations.isEmpty else {
            return CommittedChange(
                origin: .remote,
                author: sender,
                applied: [],
                invalidation: ChangeInvalidation(),
                sequence: sequence,
                documentRevision: document.documentRevision,
                isUndoable: false,
                isDirtying: false,
                rejected: rejected
            )
        }
        document.reconcileChildrenWithParents(after: &probe.journal)

        sequence += 1
        for write in writes {
            ledger.stamp(write.keys, by: write.author, at: sequence)
        }
        return CommittedChange(
            origin: .remote,
            author: sender,
            applied: [],
            invalidation: probe.invalidation(of: mutations, after: document),
            sequence: sequence,
            documentRevision: document.documentRevision,
            isUndoable: false,
            isDirtying: false,
            rejected: rejected
        )
    }

    /// The author of the replica a remote operation came from: the session's own
    /// author for its own replica — ops it made before a crash, coming back from the
    /// relay — or the introduced collaborator.
    private func author(of peer: PeerID) -> Author {
        peer == author.peerID ? author : peers[peer] ?? .unattributed(peer: peer)
    }
}
