//
//  DocumentSessionUndoKeepTheirsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Undo is per author and keeps everyone else's later work, reporting what it kept.
struct DocumentSessionUndoKeepTheirsTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))

    private func makeSession() -> DocumentSession {
        DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana)
    }

    private func set(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    // MARK: - Property and override keys

    @Test("undo after another author's later write to the same key keeps their value and reports it")
    func laterForeignWriteIsKept() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])])))
        try session.simulateForeignWrite(set("c1", ["common.name": "Claude"]), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    @Test("only the contested key is kept; the author's other keys are undone")
    func uncontestedKeysAreUndone() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana", "kind.width": 7])])))
        try session.simulateForeignWrite(set("c1", ["kind.width": 9]), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Child1")
        #expect(try NodePropertyCodec.value(at: "kind.width", of: #require(session.document.nodes["c1"])) == 9)
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "kind.width"), author: claude)])
    }

    @Test("a foreign write older than the author's edit is overwritten as usual")
    func earlierForeignWriteIsUndone() throws {
        let session = makeSession()
        try session.simulateForeignWrite(set("c1", ["common.name": "Claude"]), by: claude)
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])])))

        let change = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.kept.isEmpty)
    }

    @Test("the same person in another window is another author")
    func otherReplicaIsForeign() throws {
        let session = makeSession()
        let anaElsewhere = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana-2"))
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])])))
        try session.simulateForeignWrite(set("c1", ["common.name": "Other window"]), by: anaElsewhere)

        let change = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Other window")
        #expect(change.kept.map(\.author) == [anaElsewhere])
    }

    @Test("an override key another author wrote later is kept")
    func overrideKeyIsKept() throws {
        let session = makeSession()
        let mine = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#00ff00", "opacity": 0.5]
        ))
        let theirs = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#0000ff"]
        ))
        try session.submit(.local(LocalEdit(operations: [mine])))
        try session.simulateForeignWrite(theirs, by: claude)

        let change = try session.submit(.undo)

        guard case let .ref(data) = session.document.nodes["ref1"]?.kind else {
            Issue.record("ref1 is no longer a ref")
            return
        }
        #expect(data.descendants?["inner"]?.properties == ["fill": "#0000ff"])
        #expect(change.kept == [KeptChange(key: .override(ref: "ref1", descendant: "inner", key: "fill"), author: claude)])
    }

    @Test("a coalesced group keeps a foreign write made part-way through it")
    func coalescedGroupKeepsMidGroupWrite() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])], undoGroup: .coalesce("g"))))
        try session.simulateForeignWrite(set("c1", ["common.name": "Claude"]), by: claude)
        try session.submit(.local(LocalEdit(operations: [set("c2", ["common.name": "Ana"])], undoGroup: .coalesce("g"))))

        let change = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Claude")
        #expect(session.document.nodes["c2"]?.common.name == "Child2")
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    @Test("a redo keeps another author's write made after the undo")
    func redoKeepsTheirs() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [set("c1", ["common.name": "Ana"])])))
        try session.submit(.undo)
        try session.simulateForeignWrite(set("c1", ["common.name": "Claude"]), by: claude)

        let change = try session.submit(.redo)

        #expect(session.document.nodes["c1"]?.common.name == "Claude")
        #expect(change.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    // MARK: - Structural steps

    @Test("undoing an insert after a foreign edit inside it keeps the node and reports the edit")
    func insertWithForeignEditInsideIsKept() throws {
        let session = makeSession()
        let child = PenNode(id: "y1", common: PenNodeCommon(name: "Y"), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData(children: [child])))
        try session.submit(.local(LocalEdit(operations: [.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))])))
        try session.simulateForeignWrite(set("y1", ["common.name": "Claude's"]), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.nodes["x1"] != nil)
        #expect(session.document.nodes["y1"]?.common.name == "Claude's")
        #expect(change.kept == [KeptChange(key: .property(node: "y1", path: "common.name"), author: claude)])
    }

    @Test("undoing an insert after another author put a node inside it keeps both")
    func insertWithForeignChildIsKept() throws {
        let session = makeSession()
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData()))
        let theirs = PenNode(id: "z1", common: PenNodeCommon(name: "Z"), kind: .rectangle(PenNode.RectangleData()))
        try session.submit(.local(LocalEdit(operations: [.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))])))
        try session.simulateForeignWrite(.insertNode(EditOperation.InsertNode(node: theirs, parentID: "x1")), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.children["x1"] == ["z1"])
        #expect(Set(change.kept.map(\.key)) == [.existence(node: "z1"), .placement(node: "z1")])
        #expect(change.kept.allSatisfy { $0.author == claude })
    }

    @Test("undoing an insert nobody else touched removes it")
    func untouchedInsertIsUndone() throws {
        let session = makeSession()
        let frame = PenNode(id: "x1", common: PenNodeCommon(name: "X"), kind: .frame(PenNode.FrameData()))
        try session.submit(.local(LocalEdit(operations: [.insertNode(EditOperation.InsertNode(node: frame, parentID: "f2"))])))
        try session.simulateForeignWrite(set("c1", ["common.name": "Elsewhere"]), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.nodes["x1"] == nil)
        #expect(change.kept.isEmpty)
    }

    @Test("undoing a detach after a foreign edit inside the expansion keeps it and leaves the instance detached")
    func detachWithForeignEditInsideIsKept() throws {
        let session = makeSession()
        let detach = try session.submit(.local(LocalEdit(operations: [.detachRef(EditOperation.DetachRef(refNodeID: "ref1"))])))
        guard case let .deleteNode(delete)? = detach.applied.first?.inverse.first?.operation else {
            Issue.record("a detach's inverse starts by deleting the expansion")
            return
        }
        let expandedChild = try #require(session.document.children[delete.nodeID]?.first)
        try session.simulateForeignWrite(set(expandedChild, ["common.name": "Claude's"]), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.nodes[delete.nodeID] != nil)
        #expect(session.document.nodes["ref1"] == nil)
        #expect(change.kept == [KeptChange(key: .property(node: expandedChild, path: "common.name"), author: claude)])
    }

    @Test("undoing a move another author has since moved again keeps their placement")
    func moveMovedAgainIsKept() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0)),
        ])))
        try session.simulateForeignWrite(
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f1", index: 0)),
            by: claude
        )

        let change = try session.submit(.undo)

        #expect(session.document.children["f1"] == ["c2", "c1", "c3"])
        #expect(change.kept == [KeptChange(key: .placement(node: "c2"), author: claude)])
    }

    @Test("undoing a delete whose parent another author has since deleted keeps their delete")
    func deleteWithParentGoneIsKept() throws {
        let session = makeSession()
        try session.submit(.local(LocalEdit(operations: [.deleteNode(EditOperation.DeleteNode(nodeID: "c4"))])))
        try session.simulateForeignWrite(.deleteNode(EditOperation.DeleteNode(nodeID: "f2")), by: claude)

        let change = try session.submit(.undo)

        #expect(session.document.nodes["c4"] == nil)
        #expect(session.document.nodes["f2"] == nil)
        #expect(change.kept == [KeptChange(key: .existence(node: "f2"), author: claude)])
    }
}
