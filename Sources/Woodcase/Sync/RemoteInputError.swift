//
//  RemoteInputError.swift
//  Woodcase
//

import Foundation

/// Why a replica refused something another peer sent before letting it touch the
/// document.
///
/// Remote input is untrusted: a buggy or hostile peer can send any value a field's type
/// allows, and a relay replays what it stored to every peer that rejoins. So the
/// boundary — ``CRDTDocument/validateRemote(_:)`` for an operation,
/// ``CRDTSnapshot/validate()`` for a snapshot — refuses what would otherwise trap or
/// hang a replica, and the refusal comes back as a value the app can report: on
/// ``CommittedChange/rejected`` for a session, from
/// ``EditableDocument/applyRemote(_:)`` for a bare document. A refused
/// operation leaves the document, the clocks and the log exactly as they were.
///
/// The clock bounds are ``LamportClock/maximumLead`` and ``LamportClock/ceiling``; see
/// ``LamportClock/admits(_:after:)``.
public enum RemoteInputError: Error, Friendly {
    /// The operation's own time is further ahead of the local clock than an honest peer
    /// could be, or past the ceiling.
    ///
    /// - Parameters:
    ///   - operation: The refused operation's id.
    ///   - localTime: The local Lamport time it was judged against.
    case timeOutOfRange(operation: Timestamp, localTime: UInt64)

    /// One of the operation's dependency entries is out of range in the same way.
    ///
    /// - Parameters:
    ///   - operation: The refused operation's id.
    ///   - peer: The dependency entry's peer.
    ///   - time: The entry's time.
    ///   - localTime: The local Lamport time it was judged against.
    case dependencyOutOfRange(operation: Timestamp, peer: PeerID, time: UInt64, localTime: UInt64)

    /// A snapshot's Lamport clock or a vector clock entry is past the ceiling.
    ///
    /// - Parameter time: The out-of-range time.
    case snapshotTimeOutOfRange(time: UInt64)

    /// A snapshot's tree holds a parent cycle, which would hang the next move's cycle
    /// check.
    ///
    /// - Parameter nodeID: A node on the cycle.
    case snapshotTreeCycle(nodeID: String)

    /// A state transfer's document holds a node its CRDT state has deleted, so the two
    /// were not taken together.
    ///
    /// - Parameter nodeID: The node the document holds and the state deleted.
    case transferDisagrees(nodeID: String)
}

extension RemoteInputError: LocalizedError {
    /// A sentence saying what was refused.
    public var errorDescription: String? {
        switch self {
        case let .timeOutOfRange(operation, localTime):
            "A remote operation from \(operation.peerID.rawValue) at time \(operation.time) was refused: "
                + "it is out of range for a local clock at \(localTime)."
        case let .dependencyOutOfRange(operation, peer, time, localTime):
            "A remote operation from \(operation.peerID.rawValue) was refused: it claims \(peer.rawValue) "
                + "reached time \(time), out of range for a local clock at \(localTime)."
        case let .snapshotTimeOutOfRange(time):
            "A remote snapshot was refused: its clock time \(time) is out of range."
        case let .snapshotTreeCycle(nodeID):
            "A remote snapshot was refused: its tree has a parent cycle through \(nodeID)."
        case let .transferDisagrees(nodeID):
            "A state transfer was refused: its document holds \(nodeID), which its CRDT state deleted."
        }
    }
}
