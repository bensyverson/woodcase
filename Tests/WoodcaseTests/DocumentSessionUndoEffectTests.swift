//
//  DocumentSessionUndoEffectTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``CommittedChange/undoEffect`` says what a change did to the author's undo and redo
/// stacks, so an app mirroring them into its own undo manager acts on it rather than
/// inferring it.
struct DocumentSessionUndoEffectTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))

    private func makeSession(collaborative: Bool = false) -> DocumentSession {
        DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana, collaborative: collaborative)
    }

    private func rename(_ nodeID: String, to name: String, group: UndoGroup = .new) -> SessionOrigin {
        .local(LocalEdit(
            operations: [.setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": AnyCodable(stringLiteral: name)]))],
            undoGroup: group
        ))
    }

    // MARK: - Local edits

    @Test("a new edit opens an entry")
    func newEditOpensEntry() throws {
        let session = makeSession()
        #expect(try session.submit(rename("c1", to: "A")).undoEffect == [.openedEntry])
    }

    @Test("a coalescing edit opens an entry, the next with the same key joins it, another key opens one")
    func coalescingOpensThenJoins() throws {
        let session = makeSession()
        #expect(try session.submit(rename("c1", to: "A", group: .coalesce("drag"))).undoEffect == [.openedEntry])
        #expect(try session.submit(rename("c1", to: "B", group: .coalesce("drag"))).undoEffect == [.joinedEntry])
        #expect(try session.submit(rename("c1", to: "C", group: .coalesce("nudge"))).undoEffect == [.openedEntry])
    }

    @Test("after an undo closes the group, the same coalescing key opens a fresh entry and clears redo")
    func undoClosesTheGroup() throws {
        let session = makeSession()
        try session.submit(rename("c1", to: "A", group: .coalesce("drag")))
        try session.submit(rename("c2", to: "B", group: .new))
        try session.submit(.undo)
        let change = try session.submit(rename("c1", to: "C", group: .coalesce("drag")))
        #expect(change.undoEffect == [.openedEntry, .clearedRedo])
    }

    @Test("an edit that joins nothing clears a redo stack that held something, and reports nothing otherwise")
    func noneEditClearsRedo() throws {
        let session = makeSession()
        #expect(try session.submit(rename("c1", to: "A", group: .none)).undoEffect == [])

        try session.submit(rename("c2", to: "B"))
        try session.submit(.undo)
        #expect(session.canRedo)
        let change = try session.submit(rename("c1", to: "C", group: .none))
        #expect(change.undoEffect == [.clearedRedo])
        #expect(!session.canRedo)
    }

    @Test("an undo and a redo that apply consume their entry and file the reversal on the opposite stack")
    func undoAndRedoFileReversals() throws {
        let session = makeSession()
        #expect(try session.submit(.undo).undoEffect == [], "nothing to undo")
        #expect(try session.submit(.redo).undoEffect == [], "nothing to redo")
        try session.submit(rename("c1", to: "A"))
        #expect(try session.submit(.undo).undoEffect == [.consumedEntry, .filedReversal])
        #expect(try session.submit(.redo).undoEffect == [.consumedEntry, .filedReversal])
    }

    @Test("an undo whose every step is kept consumes its entry and files no reversal")
    func keptUndoFilesNothing() throws {
        let session = makeSession(collaborative: true)
        let peer = SessionTestPeer(claude, document: SessionTestDocuments.make().materialize())
        try peer.receive(session.submit(rename("c1", to: "Ana")))
        let theirs = EditOperation.setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Claude"]))
        let remote = try session.submit(.remote(peer.edit(theirs), from: claude))
        #expect(remote.undoEffect == [], "a collaborator's change leaves the stacks alone")

        let change = try session.submit(.undo)

        #expect(change.applied.isEmpty)
        #expect(!change.kept.isEmpty)
        #expect(change.undoEffect == [.consumedEntry])
        #expect(!session.canUndo)
        #expect(!session.canRedo)
    }
}
