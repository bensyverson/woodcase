//
//  CRDTStateTransferTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Hot Swap: a peer joins a live session from a donor's document and CRDT state, taken
/// together, and then replays what it did offline.
@MainActor
struct CRDTStateTransferTests {
    private let donorPeer = PeerID(rawValue: "donor")
    private let joinerPeer = PeerID(rawValue: "joiner")
    private let thirdPeer = PeerID(rawValue: "third")

    private func makeDoc() -> PenDocument {
        let rect = PenNode(id: "r1", common: PenNodeCommon(name: "Rect"), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "f1", common: PenNodeCommon(name: "Frame"), kind: .frame(PenNode.FrameData(children: [rect])))
        return PenDocument(children: [frame])
    }

    private func insert(_ id: String, into parentID: String?, at index: Int? = nil) -> EditOperation {
        let node = PenNode(id: id, common: PenNodeCommon(name: id), kind: .rectangle(PenNode.RectangleData()))
        return .insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: index))
    }

    private func rename(_ id: String, _ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: id, properties: ["common.name": .string(name)]))
    }

    private func expectConverged(_ a: EditableDocument, _ b: EditableDocument, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.materialize() == b.materialize(), sourceLocation: sourceLocation)
        #expect(a.parents == b.parents, sourceLocation: sourceLocation)
        #expect(a.children == b.children, sourceLocation: sourceLocation)
    }

    @Test("a joiner's document is the donor's, whatever its own file holds")
    func joinerTakesDonorDocument() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        _ = try donor.applyLocal(insert("n1", into: "f1"))
        _ = try donor.applyLocal(.setDocumentProperties(EditOperation.SetDocumentProperties(properties: ["version": "2.99"])))
        let transfer = try #require(donor.stateTransfer())

        let joiner = try EditableDocument(joining: transfer, peerID: joinerPeer)

        #expect(joiner.nodes["n1"] != nil)
        #expect(joiner.version == "2.99")
        expectConverged(donor, joiner)
        #expect(joiner.crdtDocument?.peerID == joinerPeer)
    }

    @Test("a joiner's operations carry its own peer id, not the donor's")
    func joinerSignsItsOwnOperations() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        _ = try donor.applyLocal(insert("n1", into: "f1"))
        let joiner = try EditableDocument(joining: #require(donor.stateTransfer()), peerID: joinerPeer)
        let ops = try joiner.applyLocal(rename("n1", "Joined"))
        #expect(!ops.isEmpty)
        #expect(ops.allSatisfy { $0.id.peerID == joinerPeer })
        #expect(joiner.crdtDocument?.operationLog.peerID == joinerPeer)
    }

    @Test("a transfer survives encoding, as it travels")
    func transferEncodes() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        _ = try donor.applyLocal(insert("n1", into: "f1"))
        let transfer = try #require(donor.stateTransfer())
        let decoded = try JSONDecoder().decode(CRDTStateTransfer.self, from: JSONEncoder().encode(transfer))
        #expect(decoded == transfer)
    }

    @Test("a non-collaborative document has no state to transfer")
    func plainDocumentHasNoTransfer() {
        #expect(EditableDocument(from: makeDoc()).stateTransfer() == nil)
    }

    @Test("after joining, both sides keep editing and converge")
    func editingAfterJoinConverges() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        _ = try donor.applyLocal(insert("n1", into: "f1"))
        let joiner = try EditableDocument(joining: #require(donor.stateTransfer()), peerID: joinerPeer)

        let fromJoiner = try joiner.applyLocal(insert("j1", into: "f1", at: 1))
            + joiner.applyLocal(rename("n1", "Joined"))
        let fromDonor = try donor.applyLocal(insert("d1", into: "f1", at: 1))
        donor.applyRemote(fromJoiner)
        joiner.applyRemote(fromDonor)

        expectConverged(donor, joiner)
        #expect(donor.nodes["n1"]?.common.name == "Joined")
    }

    @Test("a transfer whose document holds a node its state deleted is refused")
    func mismatchedTransferIsRefused() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        _ = try donor.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "r1")))
        var transfer = try #require(donor.stateTransfer())
        transfer.document = makeDoc()

        #expect(throws: RemoteInputError.transferDisagrees(nodeID: "r1")) {
            _ = try EditableDocument(joining: transfer, peerID: joinerPeer)
        }
    }

    // MARK: - Offline replay

    @Test("a rejoining peer replays its offline edits onto the donor's state, and the donor converges")
    func offlineReplayConverges() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        let offline = EditableDocument(from: makeDoc(), peerID: joinerPeer)
        let shared = try donor.applyLocal(insert("n1", into: "f1"))
        offline.applyRemote(shared)

        // The joiner goes offline and edits; the donor edits on.
        let offlineOps = try offline.applyLocal(insert("j1", into: "f1", at: 1))
            + offline.applyLocal(rename("n1", "Offline"))
        let donorOps = try donor.applyLocal(insert("d1", into: "f1", at: 0))

        // It rejoins from the donor, keeping its peer id, and replays.
        let joiner = try EditableDocument(joining: #require(donor.stateTransfer()), peerID: joinerPeer)
        joiner.replayOfflineOperations(offlineOps)
        #expect(joiner.crdtDocument?.heldOperations.isEmpty == true)
        #expect(joiner.nodes["j1"] != nil)

        donor.applyRemote(joiner.pendingOperations(since: donor.checkpoint()))
        expectConverged(donor, joiner)
        _ = donorOps
    }

    @Test("an offline edit whose causal past the donor lacks is held until it arrives")
    func offlineReplayWaitsForMissingPast() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        let third = EditableDocument(from: makeDoc(), peerID: thirdPeer)
        let offline = EditableDocument(from: makeDoc(), peerID: joinerPeer)

        // The joiner saw the third peer's insert; the donor has not yet.
        let fromThird = try third.applyLocal(insert("t1", into: "f1"))
        offline.applyRemote(fromThird)
        let offlineOps = try offline.applyLocal(insert("j1", into: "f1", at: 2))

        let joiner = try EditableDocument(joining: #require(donor.stateTransfer()), peerID: joinerPeer)
        joiner.replayOfflineOperations(offlineOps)
        #expect(joiner.nodes["j1"] == nil)
        #expect(joiner.crdtDocument?.heldOperations.count == offlineOps.count)

        joiner.applyRemote(fromThird)
        #expect(joiner.crdtDocument?.heldOperations.isEmpty == true)
        #expect(joiner.children["f1"] == offline.children["f1"])
    }

    @Test("an edit made while the replica's own operations are held follows them for every peer")
    func localEditFollowsHeldOwnOperations() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: donorPeer)
        let third = EditableDocument(from: makeDoc(), peerID: thirdPeer)
        let offline = EditableDocument(from: makeDoc(), peerID: joinerPeer)
        let fromThird = try third.applyLocal(insert("t1", into: "f1"))
        offline.applyRemote(fromThird)
        let offlineOps = try offline.applyLocal(rename("t1", "Offline"))

        let joiner = try EditableDocument(joining: #require(donor.stateTransfer()), peerID: joinerPeer)
        joiner.replayOfflineOperations(offlineOps)
        let fresh = try joiner.applyLocal(rename("r1", "Fresh"))
        let freshID = try #require(fresh.first).id
        #expect(offlineOps.allSatisfy { $0.id < freshID })
        #expect(try fresh.first?.dependencies.covers(#require(offlineOps.last).id) == true)

        // Another peer receives the fresh edit first: it waits for the offline one.
        donor.applyRemote(fresh)
        #expect(donor.nodes["r1"]?.common.name == "Rect")
        donor.applyRemote(fromThird)
        donor.applyRemote(offlineOps)
        joiner.applyRemote(fromThird)
        expectConverged(donor, joiner)
        #expect(donor.nodes["t1"]?.common.name == "Offline")
        #expect(donor.nodes["r1"]?.common.name == "Fresh")
    }
}
