//
//  CheckpointTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CheckpointTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")

    private func makeDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect]))
        )
        return PenDocument(children: [frame])
    }

    // MARK: - checkpoint()

    @Test("checkpoint returns current vector clock reflecting local edits")
    func checkpointReflectsLocalEdits() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edited"))
        ))

        let clock = editable.checkpoint()
        #expect(clock.time(for: peerA) > 0)
    }

    @Test("checkpoint advances after remote ops")
    func checkpointAdvancesAfterRemoteOps() throws {
        let editableA = EditableDocument(from: makeDoc(), peerID: peerA)
        let editableB = EditableDocument(from: makeDoc(), peerID: peerB)

        let opsA = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "A Edit"))
        ))

        let clockBefore = editableB.checkpoint()
        editableB.applyRemote(opsA)
        let clockAfter = editableB.checkpoint()

        // B's clock should reflect A's ops now
        #expect(clockAfter.time(for: peerA) >= clockBefore.time(for: peerA))
    }

    // MARK: - VectorClock.minimum

    @Test("VectorClock.minimum computes component-wise min across 3 clocks")
    func minimumOfThreeClocks() {
        var clockA = VectorClock()
        clockA.entries[peerA] = 5
        clockA.entries[peerB] = 3
        clockA.entries[peerC] = 7

        var clockB = VectorClock()
        clockB.entries[peerA] = 3
        clockB.entries[peerB] = 6
        clockB.entries[peerC] = 2

        var clockC = VectorClock()
        clockC.entries[peerA] = 4
        clockC.entries[peerB] = 1
        clockC.entries[peerC] = 5

        let consensus = VectorClock.minimum(of: [clockA, clockB, clockC])

        #expect(consensus.time(for: peerA) == 3)
        #expect(consensus.time(for: peerB) == 1)
        #expect(consensus.time(for: peerC) == 2)
    }

    @Test("VectorClock.minimum with empty array returns empty clock")
    func minimumOfEmptyArray() {
        let consensus = VectorClock.minimum(of: [])
        #expect(consensus.entries.isEmpty)
    }

    @Test("VectorClock.minimum with single clock returns that clock")
    func minimumOfSingleClock() {
        var clock = VectorClock()
        clock.entries[peerA] = 5
        clock.entries[peerB] = 3

        let consensus = VectorClock.minimum(of: [clock])
        #expect(consensus.time(for: peerA) == 5)
        #expect(consensus.time(for: peerB) == 3)
    }

    // MARK: - truncateLog

    @Test("truncateLog removes acknowledged ops")
    func truncateLogRemovesAcknowledged() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edit 1"))
        ))
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edit 2"))
        ))

        let opCount = try #require(editable.crdtDocument?.operationLog.operations.count)
        #expect(opCount > 0)

        // Acknowledge everything
        let fullClock = editable.checkpoint()
        editable.truncateLog(acknowledgedBy: fullClock)

        #expect(try #require(editable.crdtDocument?.operationLog.operations.isEmpty))
    }

    @Test("truncateLog preserves unacknowledged ops")
    func truncateLogPreservesUnacknowledged() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        _ = try editable.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "Edit 1"))
        ))

        // Partially acknowledge — only up to time 0 for peerA
        var partialClock = VectorClock()
        partialClock.entries[peerA] = 0
        editable.truncateLog(acknowledgedBy: partialClock)

        // Ops should still be there
        #expect(try !#require(editable.crdtDocument?.operationLog.operations.isEmpty))
    }

    // MARK: - Full checkpoint flow

    @Test("Full checkpoint flow: two peers edit, exchange checkpoints, truncate")
    func fullCheckpointFlow() throws {
        let editableA = EditableDocument(from: makeDoc(), peerID: peerA)
        let editableB = EditableDocument(from: makeDoc(), peerID: peerB)

        // Both make edits
        let opsA = try editableA.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "A Edit"))
        ))
        let opsB = try editableB.applyLocal(.updateCommon(
            EditOperation.UpdateCommon(nodeID: "r1", common: PenNodeCommon(name: "B Edit"))
        ))

        // Exchange ops
        editableA.applyRemote(opsB)
        editableB.applyRemote(opsA)

        // Both get checkpoints
        let clockA = editableA.checkpoint()
        let clockB = editableB.checkpoint()

        // Compute consensus (what all peers have seen)
        let consensus = VectorClock.minimum(of: [clockA, clockB])

        // Both truncate
        let countA = try #require(editableA.crdtDocument?.operationLog.operations.count)
        let countB = try #require(editableB.crdtDocument?.operationLog.operations.count)
        #expect(countA > 0)
        #expect(countB > 0)

        editableA.truncateLog(acknowledgedBy: consensus)
        editableB.truncateLog(acknowledgedBy: consensus)

        // After truncation, acknowledged ops should be gone
        #expect(try #require(editableA.crdtDocument?.operationLog.operations.count) < countA)
        #expect(try #require(editableB.crdtDocument?.operationLog.operations.count) < countB)
    }
}
