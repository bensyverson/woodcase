//
//  OperationLog.swift
//  Woodcase
//

import Foundation

/// An append-only log of ``CRDTOperation``s with clock management.
///
/// The operation log is the source of truth for what operations have been
/// generated locally and received remotely. It maintains a ``LamportClock``
/// for generating timestamps and a ``VectorClock`` for tracking causal
/// dependencies and determining which operations are pending.
///
/// ## Usage
///
/// ```swift
/// var log = OperationLog(peerID: myPeerID)
/// let op = log.appendLocal(payload: .deleteNode(...))
/// // Send op to other peers...
///
/// // Receive from other peer:
/// log.appendRemote(remoteOp)
/// ```
public struct OperationLog: Friendly {
    /// This peer's identifier.
    public let peerID: PeerID

    /// The Lamport clock for generating timestamps.
    public var clock: LamportClock

    /// The vector clock tracking all known peer times.
    public var vectorClock: VectorClock

    /// All operations in the log, in append order.
    public private(set) var operations: [CRDTOperation]

    /// Creates an empty operation log for the given peer.
    ///
    /// - Parameter peerID: This peer's unique identifier.
    public init(peerID: PeerID) {
        self.peerID = peerID
        clock = LamportClock()
        vectorClock = VectorClock()
        operations = []
    }

    /// Creates a log for a new replica that starts from another's: its operations and
    /// clocks, under this replica's own peer id.
    ///
    /// - Parameters:
    ///   - peerID: The new replica's identifier.
    ///   - log: The log it starts from.
    init(peerID: PeerID, adopting log: OperationLog) {
        self.peerID = peerID
        clock = log.clock
        vectorClock = log.vectorClock
        operations = log.operations
    }

    /// Appends a locally-generated operation to the log.
    ///
    /// Ticks the Lamport clock, stamps the operation with the vector clock as it stood
    /// — its causal past — and then records the operation in the vector clock.
    ///
    /// - Parameter payload: The operation payload.
    /// - Returns: The complete operation with timestamp and dependencies.
    @discardableResult
    public mutating func appendLocal(payload: CRDTOperation.Payload) -> CRDTOperation {
        appendLocal(payload: payload, following: nil)
    }

    /// ``appendLocal(payload:)``, also depending on an earlier operation of this replica's
    /// that has not been applied here yet — one being replayed from an earlier run.
    ///
    /// - Parameters:
    ///   - payload: The operation payload.
    ///   - ownTime: The time of the latest such operation, or `nil` for none.
    /// - Returns: The complete operation with timestamp and dependencies.
    mutating func appendLocal(payload: CRDTOperation.Payload, following ownTime: UInt64?) -> CRDTOperation {
        let id = Timestamp(time: clock.tick(), peerID: peerID)
        var dependencies = vectorClock
        if let ownTime {
            dependencies.record(Timestamp(time: ownTime, peerID: peerID))
        }
        let op = CRDTOperation(id: id, dependencies: dependencies, payload: payload)
        vectorClock.record(id)
        operations.append(op)
        return op
    }

    /// Appends a remotely-received operation to the log.
    ///
    /// Advances the Lamport clock past the remote timestamp, merges the operation's
    /// dependencies, and records the operation in the vector clock.
    ///
    /// - Parameter operation: The remote operation to record.
    public mutating func appendRemote(_ operation: CRDTOperation) {
        clock.witness(operation.id.time)
        vectorClock.merge(operation.dependencies)
        vectorClock.record(operation.id)
        operations.append(operation)
    }

    /// Returns operations that are not yet reflected in the given vector clock.
    ///
    /// - Parameter since: A vector clock representing the recipient's state.
    /// - Returns: Operations the clock does not ``VectorClock/covers(_:)``.
    public func pending(since: VectorClock) -> [CRDTOperation] {
        operations.filter { !since.covers($0.id) }
    }

    /// Removes operations that are acknowledged by all peers.
    ///
    /// An operation is "acknowledged" when the given vector clock's entry
    /// for the operation's peer is at least as large as the operation's time.
    ///
    /// - Parameter acknowledgedBy: A vector clock representing the minimum
    ///   state that all peers have seen.
    public mutating func truncate(acknowledgedBy: VectorClock) {
        operations.removeAll { acknowledgedBy.covers($0.id) }
    }
}
