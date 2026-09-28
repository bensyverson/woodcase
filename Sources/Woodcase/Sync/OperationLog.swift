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

    /// Appends a locally-generated operation to the log.
    ///
    /// Ticks the Lamport clock, increments the vector clock for this peer,
    /// and records the operation with its dependencies.
    ///
    /// - Parameter payload: The operation payload.
    /// - Returns: The complete operation with timestamp and dependencies.
    @discardableResult
    public mutating func appendLocal(payload: CRDTOperation.Payload) -> CRDTOperation {
        let time = clock.tick()
        vectorClock.increment(for: peerID)

        let op = CRDTOperation(
            id: Timestamp(time: time, peerID: peerID),
            dependencies: vectorClock,
            payload: payload
        )
        operations.append(op)
        return op
    }

    /// Appends a remotely-received operation to the log.
    ///
    /// Advances the Lamport clock past the remote timestamp and merges
    /// the remote vector clock.
    ///
    /// - Parameter operation: The remote operation to record.
    public mutating func appendRemote(_ operation: CRDTOperation) {
        clock.witness(operation.id.time)
        vectorClock.merge(operation.dependencies)
        operations.append(operation)
    }

    /// Returns operations that are not yet reflected in the given vector clock.
    ///
    /// - Parameter since: A vector clock representing the recipient's state.
    /// - Returns: Operations whose timestamps are newer than the recipient has seen.
    public func pending(since: VectorClock) -> [CRDTOperation] {
        operations.filter { op in
            since.time(for: op.id.peerID) < op.id.time
        }
    }

    /// Removes operations that are acknowledged by all peers.
    ///
    /// An operation is "acknowledged" when the given vector clock's entry
    /// for the operation's peer is at least as large as the operation's time.
    ///
    /// - Parameter acknowledgedBy: A vector clock representing the minimum
    ///   state that all peers have seen.
    public mutating func truncate(acknowledgedBy: VectorClock) {
        operations.removeAll { op in
            acknowledgedBy.time(for: op.id.peerID) >= op.id.time
        }
    }
}
