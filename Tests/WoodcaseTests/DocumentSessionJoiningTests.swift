//
//  DocumentSessionJoiningTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A session made from a donor's state transfer (Hot Swap): an app replaces its window's
/// session with one that holds the live session's board.
struct DocumentSessionJoiningTests {
    private let donorAuthor = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let joinerAuthor = Author(name: "bo", peerID: PeerID(rawValue: "peer-bo"))
    private let file = URL(fileURLWithPath: "/tmp/session-joining.pen")

    private let original = SessionTestDocuments.make().materialize()

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    /// A donor session that has edited past its seed, so a joiner can't pass by
    /// starting from the seed alone.
    private func makeDonor() throws -> DocumentSession {
        let donor = DocumentSession(document: original, author: donorAuthor, collaborative: true)
        try donor.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Donated"])])))
        return donor
    }

    private func transfer(from donor: DocumentSession) throws -> CRDTStateTransfer {
        try #require(donor.document.stateTransfer())
    }

    @Test("a joined session materializes the donor's document and reports its seed fingerprint")
    func joinedSessionHoldsDonorBoard() throws {
        let donor = try makeDonor()

        let joiner = try DocumentSession(joining: transfer(from: donor), author: joinerAuthor, file: file)

        #expect(joiner.document.materialize() == donor.document.materialize())
        #expect(joiner.document.nodes["c1"]?.common.name == "Donated")
        let fingerprint = try #require(donor.document.seedFingerprint)
        #expect(joiner.document.seedFingerprint == fingerprint)
        #expect(joiner.document.crdtDocument?.peerID == joinerAuthor.peerID)
        #expect(joiner.author == joinerAuthor)
        #expect(joiner.file == file)
    }

    @Test("a joined session accepts the donor's later operations")
    func joinedSessionAcceptsDonorOperations() throws {
        let donor = try makeDonor()
        let joiner = try DocumentSession(joining: transfer(from: donor), author: joinerAuthor)

        let later = try donor.submit(.local(LocalEdit(operations: [set("c2", ["common.name": "Later"])])))
        let change = try joiner.submit(.remote(later.broadcast, from: donorAuthor))

        #expect(joiner.document.nodes["c2"]?.common.name == "Later")
        #expect(change.author == donorAuthor)
        #expect(joiner.document.materialize() == donor.document.materialize())
    }

    @Test("a joined session's local edits broadcast under its own peer id, and the donor takes them")
    func joinedSessionBroadcastsToDonor() throws {
        let donor = try makeDonor()
        let joiner = try DocumentSession(joining: transfer(from: donor), author: joinerAuthor)

        let change = try joiner.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Joined"])])))

        #expect(!change.broadcast.isEmpty)
        #expect(change.broadcast.allSatisfy { $0.id.peerID == joinerAuthor.peerID })
        try donor.submit(.remote(change.broadcast, from: joinerAuthor))
        #expect(donor.document.nodes["c1"]?.common.name == "Joined")
        #expect(joiner.document.materialize() == donor.document.materialize())
    }

    @Test("a transfer that disagrees with itself is refused")
    func mismatchedTransferIsRefused() throws {
        let donor = DocumentSession(document: original, author: donorAuthor, collaborative: true)
        try donor.submit(.local(LocalEdit(operations: [.deleteNode(EditOperation.DeleteNode(nodeID: "c1"))])))
        var transfer = try transfer(from: donor)
        transfer.document = original

        #expect(throws: RemoteInputError.transferDisagrees(nodeID: "c1")) {
            _ = try DocumentSession(joining: transfer, author: joinerAuthor)
        }
    }

    @Test("a joined session counts as unsynced: its file never held the donor's board")
    func joinedSessionIsUnsynced() throws {
        let joiner = try DocumentSession(joining: transfer(from: makeDonor()), author: joinerAuthor, file: file)

        #expect(joiner.hasUnsyncedChanges)
        #expect(joiner.syncedRevision == nil)
    }

    @Test("a joined session given its file's document merges against it, and stays unsynced")
    func joinedSessionKeepsFileMergeBase() throws {
        let joiner = try DocumentSession(
            joining: transfer(from: makeDonor()),
            author: joinerAuthor,
            file: file,
            synced: original,
            merger: .threeWay
        )

        #expect(joiner.hasUnsyncedChanges)
        #expect(joiner.syncedRevision == EditableDocument(from: original).documentRevision)

        var written = original
        written.version = "2.99"
        try joiner.submit(.file(written, author: donorAuthor))
        #expect(joiner.document.version == "2.99")
        #expect(joiner.document.nodes["c1"]?.common.name == "Donated")
    }
}
