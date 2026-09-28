//
//  OperationLogTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct OperationLogTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    @Test("appendLocal increments clock and produces correct timestamp")
    func appendLocalIncrementsClock() {
        var log = OperationLog(peerID: peerA)

        let op1 = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n1")))
        #expect(op1.id.time == 1)
        #expect(op1.id.peerID == peerA)

        let op2 = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n2")))
        #expect(op2.id.time == 2)
    }

    @Test("appendRemote advances witness clock")
    func appendRemoteAdvancesWitness() {
        var log = OperationLog(peerID: peerA)

        let remoteOp = CRDTOperation(
            id: Timestamp(time: 10, peerID: peerB),
            dependencies: VectorClock(),
            payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n1"))
        )
        log.appendRemote(remoteOp)

        // Next local op should have time > 10
        let localOp = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n2")))
        #expect(localOp.id.time > 10)
    }

    @Test("pending(since:) returns correct subset")
    func pendingSince() {
        var log = OperationLog(peerID: peerA)

        let op1 = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n1")))
        let op2 = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n2")))
        let op3 = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n3")))
        _ = (op1, op3)

        // Get ops since op2's vector clock (should return op3)
        let pending = log.pending(since: op2.dependencies)
        #expect(pending.count >= 1)
        #expect(pending.contains(where: { $0.id == op3.id }))
    }

    @Test("truncate removes acknowledged ops")
    func truncateRemovesAcknowledged() {
        var log = OperationLog(peerID: peerA)

        let op1 = log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n1")))
        log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n2")))
        _ = op1

        // Create a vector clock that acknowledges op1
        var ackClock = VectorClock()
        ackClock.entries[peerA] = 1

        let countBefore = log.operations.count
        log.truncate(acknowledgedBy: ackClock)
        #expect(log.operations.count < countBefore)
    }

    @Test("OperationLog is Friendly")
    func isFriendly() throws {
        var log = OperationLog(peerID: peerA)
        log.appendLocal(payload: .deleteNode(CRDTOperation.DeleteNode(nodeID: "n1")))

        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(OperationLog.self, from: data)
        #expect(decoded.peerID == log.peerID)
        #expect(decoded.operations.count == log.operations.count)
    }
}
