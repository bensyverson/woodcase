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
    /// been introduced; one from a replica nobody introduced is credited to
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
    /// logs it), broadcasts nothing and does not dirty the file. Ordering operations
    /// whose dependencies have not arrived is not done here: they are applied as given.
    ///
    /// - Parameters:
    ///   - operations: The operations, in the order they arrived.
    ///   - sender: The collaborator who sent them, who joins the peer registry.
    /// An operation the boundary refuses (``CRDTDocument/validateRemote(_:)``) is skipped
    /// and reported on ``CommittedChange/rejected``; the rest of the batch still lands.
    ///
    /// - Returns: The committed change; with nothing accepted, an empty change that keeps
    ///   the current sequence.
    /// - Throws: ``SessionError/notCollaborative`` when the session keeps no CRDT.
    func commitRemote(_ operations: [CRDTOperation], from sender: Author) throws -> CommittedChange {
        guard document.crdtDocument != nil else { throw SessionError.notCollaborative }
        noteJoined(sender)

        var probe = ChangeInvalidation.RemoteProbe(document)
        var mutations: [DocumentMutation] = []
        var writes: [(keys: [ChangeKey], author: Author)] = []
        var rejected: [RemoteInputError] = []
        for operation in operations {
            let keys = ChangeKey.keys(ofRemote: operation, in: document)
            let applied: [DocumentMutation]
            do {
                applied = try document.applyRemoteMutations(operation, journal: &probe.journal)
            } catch {
                rejected.append(error)
                continue
            }
            guard !applied.isEmpty else { continue }
            mutations += applied
            writes.append((keys, author(of: operation.id.peerID)))
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

    /// The author of the replica a remote operation came from.
    private func author(of peer: PeerID) -> Author {
        peers[peer] ?? .unattributed(peer: peer)
    }
}
