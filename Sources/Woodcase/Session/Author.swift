//
//  Author.swift
//  Woodcase
//

import Foundation

/// Who made an edit: a name for people to read, and the replica that made it.
///
/// The ``name`` is the identity the activity log records — the `--as` name, or
/// ``ActivityEvent/unattributed`` for nobody. The ``peerID`` names one replica of the
/// document, so the same person in two windows is two authors: undo in one window
/// keeps what the other window wrote, exactly as it keeps another person's work.
/// Reports show the name only.
///
/// The peer id is also what a collaborative ``DocumentSession`` hands its
/// ``CRDTDocument``, which is the explicit mapping between the log's names and the
/// CRDT's replicas.
public struct Author: Friendly {
    /// Creates an author.
    ///
    /// - Parameters:
    ///   - name: The name the activity log records.
    ///   - peerID: The replica this author edits from.
    public init(name: String, peerID: PeerID) {
        self.name = name
        self.peerID = peerID
    }

    /// The name the activity log records; ``ActivityEvent/unattributed`` for nobody.
    public var name: String

    /// The replica this author edits from.
    public var peerID: PeerID

    /// The author of a write nobody claimed, on one replica.
    ///
    /// - Parameter peer: The replica the write came from.
    /// - Returns: An author with the log's unattributed name.
    public static func unattributed(peer: PeerID) -> Author {
        Author(name: ActivityEvent.unattributed, peerID: peer)
    }

    /// The author of a file write the activity log does not explain — an outside editor,
    /// a `git checkout` — credited for a ``SessionOrigin/file(_:author:)`` merge with no
    /// author. Unattributed, on a replica of its own, so the local author's undo keeps
    /// what it wrote.
    public static let external = Author.unattributed(peer: PeerID(rawValue: "__external__"))
}
