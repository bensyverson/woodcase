//
//  CRDTDocument+RemoteValidation.swift
//  Woodcase
//

import Foundation

public extension CRDTDocument {
    /// Checks a remote operation against the boundary's bounds without changing anything.
    ///
    /// ``processRemote(operation:document:)`` runs this first and drops an operation it
    /// refuses, so a refused operation is never logged, witnessed or applied. The
    /// operation's own time and every dependency entry must be admitted by
    /// ``LamportClock/admits(_:after:)`` against the local Lamport time. Every other
    /// remote value — ids, property paths, values, list positions — is safe to apply as
    /// given: an unknown id or path, or a value that does not decode, is a no-op.
    ///
    /// - Parameter operation: The operation a peer sent.
    /// - Throws: ``RemoteInputError/timeOutOfRange(operation:localTime:)`` or
    ///   ``RemoteInputError/dependencyOutOfRange(operation:peer:time:localTime:)``.
    func validateRemote(_ operation: CRDTOperation) throws(RemoteInputError) {
        let localTime = operationLog.clock.time
        guard LamportClock.admits(operation.id.time, after: localTime) else {
            throw .timeOutOfRange(operation: operation.id, localTime: localTime)
        }
        // Sorted, so the refusal a caller sees does not depend on dictionary order.
        for (peer, time) in operation.dependencies.entries.sorted(by: { $0.key < $1.key })
            where !LamportClock.admits(time, after: localTime)
        {
            throw .dependencyOutOfRange(operation: operation.id, peer: peer, time: time, localTime: localTime)
        }
    }
}
