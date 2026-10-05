//
//  DocumentSessionFileTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `submit(.file)` folds the file's document into the live one through a
/// ``DocumentMerger``, under the file's author.
struct DocumentSessionFileTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
    private let claude = Author(name: "claude", peerID: PeerID(rawValue: "peer-claude"))
    private let file = URL(fileURLWithPath: "/tmp/session-file.pen")

    /// A merger that returns a fixed result and remembers what it was asked.
    private final class StubMerger: DocumentMerger {
        let result: MergeResult
        private(set) var calls: [(base: PenDocument, ours: PenDocument, theirs: PenDocument)] = []

        init(_ result: MergeResult) {
            self.result = result
        }

        func merge(base: EditableDocument, ours: EditableDocument, theirs: EditableDocument) -> MergeResult {
            calls.append((base.materialize(), ours.materialize(), theirs.materialize()))
            return result
        }
    }

    private static func rename(_ nodeID: String, to name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": .string(name)]))
    }

    private func makeSession(
        merger: (any DocumentMerger)?,
        collaborative: Bool = false,
        file: URL? = nil
    ) -> DocumentSession {
        DocumentSession(
            document: SessionTestDocuments.make().materialize(),
            author: ana,
            file: file,
            collaborative: collaborative,
            merger: merger
        )
    }

    /// The session's document with `edits` applied, as the file would hold it.
    private func fileDocument(_ session: DocumentSession, _ edits: [EditOperation]) throws -> PenDocument {
        let copy = EditableDocument(from: session.document.materialize())
        for edit in edits {
            try copy.apply(edit)
        }
        return copy.materialize()
    }

    private static let conflict = MergeConflict(
        subject: .property(nodeID: "c2", path: "common.name"), kind: .bothChanged,
        base: "Child2", ours: "Mine", theirs: "Theirs"
    )

    // MARK: - With a stub merger

    @Test("a file merge applies the merger's ops under the file author, pushing no undo")
    func stubAppliesUnderFileAuthor() throws {
        let stub = StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")], conflicts: [Self.conflict]))
        let session = makeSession(merger: stub, file: file)
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        let change = try session.submit(.file(theirs, author: claude))

        #expect(change.origin == .file)
        #expect(change.author == claude)
        #expect(change.applied.map(\.forward) == [Self.rename("c1", to: "Theirs")])
        #expect(change.applied.first?.inverse.map(\.operation) == [Self.rename("c1", to: "Child1")])
        #expect(change.sequence == 1)
        #expect(change.documentRevision == session.document.documentRevision)
        #expect(change.invalidation.nodes.contains("c1"))
        #expect(change.conflicts == [Self.conflict])
        #expect(!change.isUndoable)
        #expect(change.activity.isEmpty)
        #expect(session.document.nodes["c1"]?.common.name == "Theirs")
        #expect(!session.canUndo)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.author == claude)
    }

    @Test("a file merge passes the merger the synced base, the live document and the file's document")
    func stubSeesThreeSides() throws {
        let stub = StubMerger(MergeResult())
        let session = makeSession(merger: stub)
        let synced = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [Self.rename("c2", to: "Local")])))
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        try session.submit(.file(theirs, author: claude))

        let call = try #require(stub.calls.first)
        #expect(stub.calls.count == 1)
        #expect(call.base == synced)
        #expect(call.ours == session.document.materialize())
        #expect(call.theirs == theirs)
    }

    @Test("a file merge advances the merge base to the file's document")
    func stubAdvancesBase() throws {
        let session = makeSession(merger: StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")])))
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        try session.submit(.file(theirs, author: claude))

        #expect(session.base?.materialize() == theirs)
    }

    @Test("a file merge that keeps no local work leaves the session in sync with its file")
    func mergeWithoutLocalWorkIsClean() throws {
        let session = makeSession(merger: StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")])))
        try session.submit(.local(LocalEdit(operations: [Self.rename("c1", to: "Mine")])))
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        let change = try session.submit(.file(theirs, author: claude))

        #expect(!change.isDirtying)
        #expect(!session.hasUnsyncedChanges)
        #expect(session.syncedSequence == change.sequence)
    }

    @Test("a file merge that keeps local work leaves the session dirty")
    func mergeKeepingLocalWorkStaysDirty() throws {
        let session = makeSession(merger: StubMerger(MergeResult(
            operations: [Self.rename("c1", to: "Theirs")], keepsLocalChanges: true
        )))
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        let change = try session.submit(.file(theirs, author: claude))

        #expect(change.isDirtying)
        #expect(session.hasUnsyncedChanges)
    }

    @Test("a file merge with nothing to apply keeps the sequence but still advances the base")
    func emptyMergeKeepsSequence() throws {
        let session = makeSession(merger: StubMerger(MergeResult(conflicts: [Self.conflict], keepsLocalChanges: true)))
        try session.submit(.local(LocalEdit(operations: [Self.rename("c2", to: "Mine")])))
        let theirs = try fileDocument(session, [])

        let change = try session.submit(.file(theirs, author: claude))

        #expect(change.applied.isEmpty)
        #expect(change.sequence == 1)
        #expect(change.conflicts == [Self.conflict])
        #expect(session.base?.materialize() == theirs)
        #expect(session.hasUnsyncedChanges)
    }

    @Test("an outside writer's merge is credited to the external author")
    func nilAuthorIsExternal() throws {
        let session = makeSession(merger: StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")])))
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        let change = try session.submit(.file(theirs, author: nil))

        #expect(change.author == .external)
        #expect(change.author.name == ActivityEvent.unattributed)
        #expect(change.author != ana)
    }

    @Test("the local author's undo keeps a key the file merge wrote since")
    func undoKeepsFileWrite() throws {
        let session = makeSession(merger: StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")])))
        try session.submit(.local(LocalEdit(operations: [Self.rename("c1", to: "Mine")])))
        session.noteSynced(session.document.materialize(), through: session.sequence)
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])
        try session.submit(.file(theirs, author: claude))

        let undo = try session.submit(.undo)

        #expect(session.document.nodes["c1"]?.common.name == "Theirs")
        #expect(undo.kept == [KeptChange(key: .property(node: "c1", path: "common.name"), author: claude)])
    }

    @Test("a file merge in a collaborative session broadcasts its operations")
    func collaborativeMergeBroadcasts() throws {
        let session = makeSession(
            merger: StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")])),
            collaborative: true
        )
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        let change = try session.submit(.file(theirs, author: claude))

        #expect(!change.broadcast.isEmpty)
    }

    @Test("a file merge whose ops fail part-way leaves the session as it was")
    func failedMergeIsAtomic() throws {
        let session = makeSession(merger: StubMerger(MergeResult(operations: [
            Self.rename("c1", to: "Theirs"),
            Self.rename("missing", to: "Nowhere"),
        ])))
        let before = session.document.materialize()
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        #expect(throws: EditingError.self) { try session.submit(.file(theirs, author: claude)) }

        #expect(session.document.materialize() == before)
        #expect(session.sequence == 0)
        #expect(session.base?.materialize() == before)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name")) == nil)
    }

    // MARK: - With the real three-way merge

    @Test("an unwritten local change survives a file merge, and the same-key conflict is reported")
    func realMergeKeepsLocalWork() throws {
        let session = makeSession(merger: .threeWay, file: file)
        try session.submit(.local(LocalEdit(operations: [Self.rename("c1", to: "Mine")])))
        let theirs = try fileDocument(
            DocumentSession(document: SessionTestDocuments.make().materialize(), author: claude),
            [Self.rename("c1", to: "Theirs"), Self.rename("c2", to: "TheirC2")]
        )

        let change = try session.submit(.file(theirs, author: claude))

        #expect(session.document.nodes["c1"]?.common.name == "Mine")
        #expect(session.document.nodes["c2"]?.common.name == "TheirC2")
        #expect(change.conflicts.contains { conflict in
            conflict.subject == .property(nodeID: "c1", path: "common.name") && conflict.kind == .bothChanged
        })
        #expect(change.isDirtying)
        #expect(session.hasUnsyncedChanges)
        #expect(session.base?.materialize() == theirs)
        #expect(session.ledger.stamp(for: .property(node: "c2", path: "common.name"))?.author == claude)
        #expect(session.ledger.stamp(for: .property(node: "c1", path: "common.name"))?.author == ana)
    }

    @Test("the real merge of a file that only adds to the base leaves the session clean")
    func realMergeOfExternalOnlyIsClean() throws {
        let session = makeSession(merger: .threeWay)
        let theirs = try fileDocument(session, [Self.rename("c2", to: "TheirC2")])

        let change = try session.submit(.file(theirs, author: claude))

        #expect(session.document.materialize() == theirs)
        #expect(change.conflicts.isEmpty)
        #expect(!session.hasUnsyncedChanges)
    }

    // MARK: - Refusals

    @Test("a file merge without a merger throws mergeUnavailable")
    func noMergerThrows() throws {
        let session = makeSession(merger: nil)
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        #expect(throws: SessionError.mergeUnavailable) { try session.submit(.file(theirs, author: claude)) }
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
        #expect(session.sequence == 0)
    }

    @Test("a file merge into a session that never knew its file state throws fileStateUnknown")
    func unknownBaseThrows() throws {
        let stub = StubMerger(MergeResult(operations: [Self.rename("c1", to: "Theirs")]))
        let session = DocumentSession(editing: SessionTestDocuments.make(), author: ana, file: nil, merger: stub)
        let theirs = try fileDocument(session, [Self.rename("c1", to: "Theirs")])

        #expect(throws: SessionError.fileStateUnknown) { try session.submit(.file(theirs, author: claude)) }
        #expect(stub.calls.isEmpty)
        #expect(session.document.nodes["c1"]?.common.name == "Child1")
    }
}
