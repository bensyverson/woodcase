//
//  DocumentSessionLocalTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `submit(.local)` applies an edit and describes it in one ``CommittedChange``.
struct DocumentSessionLocalTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let file = URL(fileURLWithPath: "/tmp/session-local.pen")

    private func makeSession(collaborative: Bool = false, file: URL? = nil) -> DocumentSession {
        DocumentSession(
            document: SessionTestDocuments.make().materialize(),
            author: ana,
            file: file,
            collaborative: collaborative
        )
    }

    private func rename(_ nodeID: String, to name: String, in session: DocumentSession) throws -> EditOperation {
        var common = try #require(session.document.nodes[nodeID]).common
        common.name = name
        return .updateCommon(EditOperation.UpdateCommon(nodeID: nodeID, common: common))
    }

    // MARK: - The change value

    @Test("a local rename returns the normalized forward op, its inverse, sequence and revision")
    func renameDescribesItself() throws {
        let session = makeSession(file: file)
        let change = try session.submit(.local(LocalEdit(operations: [rename("c1", to: "Renamed", in: session)])))

        #expect(change.origin == .local)
        #expect(change.author == ana)
        #expect(change.sequence == 1)
        #expect(session.sequence == 1)
        #expect(change.documentRevision == session.document.documentRevision)
        #expect(change.applied.count == 1)
        #expect(change.applied.first?.forward == .setProperties(EditOperation.SetProperties(
            nodeID: "c1", properties: ["common.name": "Renamed"]
        )))
        #expect(change.applied.first?.inverse.map(\.operation) == [.setProperties(EditOperation.SetProperties(
            nodeID: "c1", properties: ["common.name": "Child1"]
        ))])
        #expect(change.isUndoable)
        #expect(change.isDirtying)
        #expect(change.kept.isEmpty)
        #expect(change.broadcast.isEmpty)
        #expect(session.document.nodes["c1"]?.common.name == "Renamed")
    }

    @Test("a local edit records one activity event per operation, under the author's name")
    func activityEvents() throws {
        let session = makeSession(file: file)
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0))
        let change = try session.submit(.local(LocalEdit(operations: [rename("c1", to: "Renamed", in: session), move])))

        #expect(change.activity.count == 2)
        #expect(change.activity.map(\.identity) == ["ana", "ana"])
        #expect(change.activity.map(\.op) == [.set, .mv])
        #expect(change.activity.last?.nodes == ["c2", "f2"])
        #expect(change.activity.last?.revision == session.document.documentRevision)
        #expect(change.activity.first?.inverse == change.applied.first?.inverse.map(\.operation))
        #expect(Set(change.activity.compactMap(\.batch)).count == 1)
        #expect(change.activity.first?.file == ActivityEvent.canonicalPath(for: file))
    }

    @Test("a caller-supplied activity kind labels every event")
    func activityKindOverride() throws {
        let session = makeSession(file: file)
        let copy = PenNode(id: "copy1", common: PenNodeCommon(name: "Copy"), kind: .rectangle(PenNode.RectangleData()))
        let change = try session.submit(.local(LocalEdit(
            operations: [.insertNode(EditOperation.InsertNode(node: copy, parentID: "f2"))],
            activityKind: .cp
        )))
        #expect(change.activity.map(\.op) == [.cp])
    }

    @Test("a session with no file records no activity")
    func noFileNoActivity() throws {
        let session = makeSession()
        let change = try session.submit(.local(LocalEdit(operations: [rename("c1", to: "Renamed", in: session)])))
        #expect(change.activity.isEmpty)
        #expect(change.applied.count == 1)
    }

    @Test("undoGroup .none is applied and dirtying but not undoable")
    func notUndoable() throws {
        let session = makeSession()
        let change = try session.submit(.local(LocalEdit(
            operations: [rename("c1", to: "Renamed", in: session)],
            undoGroup: .none
        )))
        #expect(!change.isUndoable)
        #expect(change.isDirtying)
    }

    @Test("an empty edit changes nothing and takes no sequence number")
    func emptyEdit() throws {
        let session = makeSession(file: file)
        let change = try session.submit(.local(LocalEdit(operations: [])))
        #expect(change.applied.isEmpty)
        #expect(change.sequence == 0)
        #expect(!change.isUndoable)
        #expect(!change.isDirtying)
        #expect(change.activity.isEmpty)
    }

    // MARK: - Sequence and ledger

    @Test("each change takes the next sequence and stamps its keys in the ledger")
    func ledgerStamps() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [rename("c1", to: "One", in: session)])))
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2"))
        let second = try session.submit(.local(LocalEdit(operations: [move])))

        #expect(second.sequence == 2)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))
            == ChangeLedger.Stamp(author: ana, sequence: 1))
        #expect(session.ledger.stamp(for: .placement(node: "c2")) == ChangeLedger.Stamp(author: ana, sequence: 2))
        #expect(session.ledger.stamp(for: .placement(node: "c1")) == nil)
    }

    // MARK: - Revision guard

    @Test("a stale expected revision refuses the whole edit")
    func staleRevision() throws {
        let session = makeSession(file: file)
        let before = session.document.materialize()
        let edit = try LocalEdit(operations: [rename("c1", to: "Renamed", in: session)], expecting: ["c1": "stale"])

        #expect(throws: EditingError.self) { try session.submit(.local(edit)) }
        #expect(session.document.materialize() == before)
        #expect(session.sequence == 0)
    }

    @Test("a current expected revision lets the edit through")
    func currentRevision() throws {
        let session = makeSession()
        let revision = try #require(session.document.revision(of: "c1"))
        let edit = try LocalEdit(operations: [rename("c1", to: "Renamed", in: session)], expecting: ["c1": revision])
        try session.submit(.local(edit))
        #expect(session.document.nodes["c1"]?.common.name == "Renamed")
    }

    // MARK: - Collaborative mode

    @Test("a collaborative session broadcasts CRDT ops a peer converges on")
    func collaborativeBroadcast() throws {
        let session = makeSession(collaborative: true)
        let peer = EditableDocument(from: SessionTestDocuments.make().materialize(), peerID: PeerID(rawValue: "peer-bo"))
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0))
        let change = try session.submit(.local(LocalEdit(operations: [rename("c1", to: "Renamed", in: session), move])))

        #expect(session.document.crdtDocument?.peerID == ana.peerID)
        #expect(!change.broadcast.isEmpty)
        peer.applyRemote(change.broadcast)
        #expect(peer.materialize() == session.document.materialize())
    }

    @Test("a solo session has no CRDT document")
    func soloHasNoCRDT() {
        #expect(makeSession().document.crdtDocument == nil)
    }

    // MARK: - Origins not yet supported

    @Test("undo, redo, file and remote origins are refused until their leaves land")
    func unsupportedOrigins() throws {
        let session = makeSession()
        let document = session.document.materialize()
        #expect(throws: SessionError.unsupportedOrigin(.undo)) { try session.submit(.undo) }
        #expect(throws: SessionError.unsupportedOrigin(.redo)) { try session.submit(.redo) }
        #expect(throws: SessionError.unsupportedOrigin(.file)) { try session.submit(.file(document, author: nil)) }
        #expect(throws: SessionError.unsupportedOrigin(.remote)) { try session.submit(.remote([], from: ana)) }
    }

    // MARK: - Author

    @Test("an unattributed author has the log's empty name")
    func unattributedAuthor() {
        let author = Author.unattributed(peer: PeerID(rawValue: "p"))
        #expect(author.name == ActivityEvent.unattributed)
        #expect(author.peerID == PeerID(rawValue: "p"))
    }
}
