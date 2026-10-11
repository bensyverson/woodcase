//
//  CommittedChangeFoldingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An app that commits every keystroke folds a typing step's changes into one before it
/// saves (``CommittedChange/folding(_:)``), so the step reaches the log as one row whose
/// inverse restores the step's start and whose forward gives its end.
struct CommittedChangeFoldingTests {
    private let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))

    private func openSession(_ url: URL) throws -> DocumentSession {
        try DocumentSession(document: PenParser.parse(contentsOf: url), author: ben, file: url, merger: .threeWay)
    }

    /// Types `word` into the fixture node's name a character at a time, one commit per
    /// keystroke, coalesced into one undo entry as a text editor does.
    private func type(_ word: String, in session: DocumentSession, from start: String = "") throws -> [CommittedChange] {
        var typed = start
        return try word.map { character in
            typed.append(character)
            return try session.submit(.local(LocalEdit(operations: [SaveFixture.rename(typed)], undoGroup: .coalesce("typing"))))
        }
    }

    // MARK: - The folded change

    @Test("a typed word folds into one row whose inverse restores the start and whose forward gives the end")
    func typedWordFoldsIntoOneRow() throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let start = session.document.documentRevision
        let startDocument = session.snapshot().document
        let changes = try type("hello", in: session)

        let folded = try #require(CommittedChange.folding(changes))

        #expect(folded.activity.count == 1)
        let row = try #require(folded.activity.first)
        #expect(row.op == .set)
        #expect(row.nodes == [SaveFixture.nodeID])
        #expect(row.revision == changes.last?.documentRevision)
        #expect(row.inverse.count == 1)
        #expect(row.forward == [SaveFixture.rename("hello")])
        let end = EditableDocument(from: session.snapshot().document)
        for step in row.inverse {
            try end.apply(step)
        }
        #expect(end.documentRevision == start)
        let replayed = EditableDocument(from: startDocument)
        for step in row.forward {
            try replayed.apply(step)
        }
        #expect(replayed.documentRevision == session.document.documentRevision)
    }

    @Test("the folded change carries the last change's numbers and every change's operations")
    func foldedChangeCarriesTheRun() throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let session = try openSession(fixture.copy())
        let changes = try type("abc", in: session)

        let folded = try #require(CommittedChange.folding(changes))

        #expect(folded.sequence == changes.last?.sequence)
        #expect(folded.documentRevision == changes.last?.documentRevision)
        #expect(folded.applied == changes.flatMap(\.applied))
        #expect(folded.origin == .local)
        #expect(folded.author == ben)
        #expect(folded.isDirtying)
        #expect(folded.isUndoable)
        #expect(folded.undoEffect.contains(.openedEntry))
        #expect(folded.undoEffect.contains(.joinedEntry))
        #expect(folded.invalidation == changes.map(\.invalidation).reduce(into: ChangeInvalidation()) { $0.formUnion($1) })
    }

    @Test("rows of another kind or on other nodes stay rows of their own")
    func otherKindsStaySeparate() throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let other = try fixture.otherNode(in: url)
        var changes = try type("ab", in: session)
        try changes.append(session.submit(.local(LocalEdit(operations: [SaveFixture.rename("Other", node: other)]))))
        try changes.append(session.submit(.local(LocalEdit(operations: [
            .moveNode(EditOperation.MoveNode(nodeID: SaveFixture.nodeID, newParentID: nil, index: 0)),
        ]))))

        let folded = try #require(CommittedChange.folding(changes))

        #expect(folded.activity.map(\.nodes.first) == [SaveFixture.nodeID, other, SaveFixture.nodeID])
        #expect(folded.activity.map(\.op) == [.set, .set, .mv])
    }

    @Test("writes of different paths on one node keep every path's inverse")
    func differentPathsKeepTheirInverses() throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let session = try openSession(fixture.copy())
        let start = session.document.documentRevision
        let changes = try [
            session.submit(.local(LocalEdit(operations: [SaveFixture.rename("A")]))),
            session.submit(.local(LocalEdit(operations: [
                .setProperties(EditOperation.SetProperties(nodeID: SaveFixture.nodeID, properties: ["common.opacity": .double(0.5)])),
            ]))),
            session.submit(.local(LocalEdit(operations: [SaveFixture.rename("AB")]))),
        ]

        let folded = try #require(CommittedChange.folding(changes))

        #expect(folded.activity.count == 1)
        let row = try #require(folded.activity.first)
        #expect(row.inverse.count == 2)
        #expect(row.forward.count == 2)
        let end = EditableDocument(from: session.snapshot().document)
        for step in row.inverse {
            try end.apply(step)
        }
        #expect(end.documentRevision == start)
    }

    @Test("one author's local changes fold; nothing, or changes of different origins or authors, do not")
    func refusesWhatIsNotOneRun() throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let session = try openSession(fixture.copy())
        let changes = try type("ab", in: session)
        var other = try #require(changes.last)
        other.author = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
        var remote = try #require(changes.last)
        remote.origin = .remote

        #expect(CommittedChange.folding(changes) != nil)
        #expect(CommittedChange.folding([]) == nil)
        #expect(CommittedChange.folding(changes + [other]) == nil)
        #expect(CommittedChange.folding(changes + [remote]) == nil)
    }

    // MARK: - Saving, undo and the merge path

    @Test("a folded step saves one row, no merge row, and an agent's undo restores the start")
    func foldedSaveIsOneUndoableRow() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let before = try Data(contentsOf: url)
        let session = try openSession(url)
        let folded = try #require(try CommittedChange.folding(type("hello", in: session)))

        let outcome = try await PenFileTransaction.save(session.snapshot(), changes: [folded], to: url, log: fixture.log)

        #expect(outcome == .wrote)
        #expect(try fixture.events(for: url).map(\.op) == [.set])
        let result = try await PenFileTransaction.run(at: url, identity: "ben", log: fixture.log) { document, recorder in
            try ActivityUndo.reverse(in: document, through: recorder, editing: url, log: fixture.log, identity: "ben")
        }.value
        #expect(result.stopped == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("a file merge after a folded step still gets its merge row")
    func mergeAfterFoldedStep() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let other = try fixture.otherNode(in: url)
        let folded = try #require(try CommittedChange.folding(type("hi", in: session)))
        let theirs = try EditableDocument(from: PenParser.parse(contentsOf: url))
        try theirs.apply(SaveFixture.rename("Agent", node: other))
        // An outside writer that logs nothing, so only a merge row can explain it.
        try PenParser.encodeForFile(theirs.materialize()).write(to: url)
        let merged = try session.submit(.file(theirs.materialize(), author: nil))

        try await PenFileTransaction.save(session.snapshot(), changes: [folded, merged], to: url, log: fixture.log)

        let rows = try fixture.events(for: url)
        #expect(rows.map(\.op) == [.set, .merge])
        #expect(rows.last?.nodes.contains(other) == true)
        #expect(rows.last?.revision == session.document.documentRevision)
    }

    @Test("the session's own undo and redo of a folded, saved step save as before")
    func sessionUndoRedoAfterFoldedSave() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let before = try Data(contentsOf: url)
        let session = try openSession(url)
        let folded = try #require(try CommittedChange.folding(type("hello", in: session)))
        let snapshot = session.snapshot()
        try await PenFileTransaction.save(snapshot, changes: [folded], to: url, log: fixture.log)
        session.noteSynced(snapshot)
        let typed = try Data(contentsOf: url)

        let undo = try session.submit(.undo)
        let undone = session.snapshot()
        try await PenFileTransaction.save(undone, changes: [undo], to: url, log: fixture.log)
        session.noteSynced(undone)
        #expect(try Data(contentsOf: url) == before)

        let redo = try session.submit(.redo)
        try await PenFileTransaction.save(session.snapshot(), changes: [redo], to: url, log: fixture.log)
        #expect(try Data(contentsOf: url) == typed)
        let ops = try fixture.events(for: url).map(\.op)
        #expect(ops.first == .set)
        #expect(ops.count(where: { $0 == .set }) == 1)
        #expect(ops.contains(.undo))
        #expect(ops.last == .redo)
    }
}
