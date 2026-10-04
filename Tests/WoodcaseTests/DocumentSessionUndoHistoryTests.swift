//
//  DocumentSessionUndoHistoryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The local author's undo and redo stacks: what an undo returns, what joins an entry,
/// what clears redo, and detaches round-tripping through both.
struct DocumentSessionUndoHistoryTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let file = URL(fileURLWithPath: "/tmp/session-undo.pen")

    private func makeSession(collaborative: Bool = false, file: URL? = nil) -> DocumentSession {
        DocumentSession(
            document: SessionTestDocuments.make().materialize(),
            author: ana,
            file: file,
            collaborative: collaborative
        )
    }

    private func rename(_ nodeID: String, to name: String, group: UndoGroup = .new) -> SessionOrigin {
        .local(LocalEdit(
            operations: [.setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": AnyCodable(stringLiteral: name)]))],
            undoGroup: group
        ))
    }

    // MARK: - The undo change

    @Test("an undo is a new change: undo origin, next sequence, stamped, logged and dirtying")
    func undoDescribesItself() throws {
        let session = makeSession(file: file)
        try session.submit(rename("c1", to: "Renamed"))

        let change = try session.submit(.undo)

        #expect(change.origin == .undo)
        #expect(change.author == ana)
        #expect(change.sequence == 2)
        #expect(change.isDirtying)
        #expect(change.applied.map(\.forward) == [.setProperties(EditOperation.SetProperties(
            nodeID: "c1", properties: ["common.name": "Child1"]
        ))])
        #expect(change.activity.map(\.op) == [.undo])
        #expect(change.invalidation.nodes.contains("c1"))
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.sequence == 2)
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
    }

    @Test("undo and redo with empty stacks change nothing")
    func emptyStacks() throws {
        let session = makeSession()
        #expect(!session.canUndo)
        #expect(!session.canRedo)

        let undo = try session.submit(.undo)
        let redo = try session.submit(.redo)

        #expect(undo.applied.isEmpty)
        #expect(redo.applied.isEmpty)
        #expect(!undo.isDirtying)
        #expect(session.sequence == 0)
    }

    @Test("undo then redo restores the edit, moving the entry between the stacks")
    func undoRedoRoundTrip() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "Renamed"))
        #expect(session.canUndo)

        try session.submit(.undo)
        #expect(!session.canUndo)
        #expect(session.canRedo)

        let redo = try session.submit(.redo)
        #expect(redo.origin == .redo)
        #expect(session.document.nodes["c1"]?.common.name == "Renamed")
        #expect(session.canUndo)
        #expect(!session.canRedo)
    }

    @Test("a redo's activity rows are labeled redo, not by their operations")
    func redoRowsAreLabeledRedo() throws {
        let session = makeSession(file: file)
        try session.submit(rename("c1", to: "Renamed"))
        try session.submit(.undo)

        let redo = try session.submit(.redo)

        #expect(redo.activity.map(\.op) == [.redo])
        #expect(ActivityEvent.Kind.redo.rawValue == "redo")
    }

    // MARK: - Clearing redo and coalescing

    @Test("a new local edit clears redo")
    func newEditClearsRedo() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "Renamed"))
        try session.submit(.undo)
        #expect(session.canRedo)

        try session.submit(rename("c2", to: "Other"))

        #expect(!session.canRedo)
        let redo = try session.submit(.redo)
        #expect(redo.applied.isEmpty)
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
    }

    @Test("a coalesced group undoes as one")
    func coalescedGroupUndoesAsOne() throws {
        let session = makeSession()
        let before = session.document.materialize()
        for step in 1 ... 3 {
            try session.submit(.local(LocalEdit(
                operations: [.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: step.isMultiple(of: 2) ? "f1" : "f2", index: 0))],
                undoGroup: .coalesce("drag")
            )))
        }
        try session.submit(rename("c2", to: "Renamed", group: .coalesce("drag")))

        try session.submit(.undo)

        #expect(session.document.materialize() == before)
        #expect(!session.canUndo)
    }

    @Test("a different coalescing key, or a new entry, starts another entry")
    func groupsBreak() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "A1", group: .coalesce("a")))
        try session.submit(rename("c1", to: "A2", group: .coalesce("a")))
        try session.submit(rename("c1", to: "B", group: .coalesce("b")))
        try session.submit(rename("c1", to: "New"))
        try session.submit(rename("c1", to: "A3", group: .coalesce("a")))

        try session.submit(.undo)
        #expect(session.document.nodes["c1"]?.common.name == "New")
        try session.submit(.undo)
        #expect(session.document.nodes["c1"]?.common.name == "B")
        try session.submit(.undo)
        #expect(session.document.nodes["c1"]?.common.name == "A2")
        try session.submit(.undo)
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
        #expect(!session.canUndo)
    }

    @Test("an edit that joins no undo entry is not undoable on its own")
    func ungroupedEditIsSkipped() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "Undoable"))
        try session.submit(rename("c2", to: "Tidy", group: .none))

        try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Child1")
        #expect(session.document.nodes["c2"]?.common.name == "Tidy")
    }

    @Test("an undo after the stack's own undo does not reopen a coalesced group")
    func undoClosesTheGroup() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "First", group: .coalesce("a")))
        try session.submit(rename("c2", to: "Second", group: .coalesce("b")))
        try session.submit(.undo)
        try session.submit(rename("c2", to: "Third", group: .coalesce("a")))

        try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "First")
        #expect(session.document.nodes["c2"]?.common.name == "Child2")
    }

    // MARK: - Detach round trips

    @Test("a detach round-trips through undo and redo", arguments: [false, true])
    func detachRoundTrip(collaborative: Bool) throws {
        let session = makeSession(collaborative: collaborative)
        let before = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [.detachRef(EditOperation.DetachRef(refNodeID: "ref1"))])))
        let detached = session.document.materialize()

        let undo = try session.submit(.undo)
        #expect(session.document.materialize() == before)
        #expect(undo.kept.isEmpty)
        #expect(undo.broadcast.isEmpty == !collaborative)

        try session.submit(.redo)
        #expect(session.document.materialize() == detached)

        try session.submit(.undo)
        #expect(session.document.materialize() == before)
    }

    @Test("a detaching delete round-trips through undo and redo", arguments: [false, true])
    func detachingDeleteRoundTrip(collaborative: Bool) throws {
        let session = makeSession(collaborative: collaborative)
        let before = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [
            .deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach)),
        ])))
        let deleted = session.document.materialize()

        try session.submit(.undo)
        #expect(session.document.materialize() == before)

        try session.submit(.redo)
        #expect(session.document.materialize() == deleted)

        try session.submit(.undo)
        #expect(session.document.materialize() == before)
    }

    // MARK: - Rollback

    @Test("a rollback restores the undo and redo stacks with the document")
    func rollbackRestoresStacks() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "Kept"))
        try session.submit(rename("c2", to: "Undone"))
        try session.submit(.undo)
        let checkpoint = session.checkpoint()

        try session.submit(rename("c3", to: "Rolled back"))
        session.rollback(to: checkpoint)

        #expect(session.canRedo)
        try session.submit(.redo)
        #expect(session.document.nodes["c2"]?.common.name == "Undone")
        try session.submit(.undo)
        try session.submit(.undo)
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
        #expect(session.document.nodes["c3"]?.common.name == "Child3")
    }
}
