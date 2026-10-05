//
//  PenFileTransactionSaveMergeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A save after the session folded in work that wrote no rows of its own — a file merge
/// that kept local work — appends a `merge` row, so the log still explains the file.
struct PenFileTransactionSaveMergeTests {
    private let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))

    /// What one merge-then-save left behind.
    private struct Saved {
        let url: URL
        let other: String
        let original: String
        let session: DocumentSession
        let snapshot: DocumentSnapshot
    }

    /// Claude renames another node through the CLI while ben's session holds an unsaved
    /// rename of ``SaveFixture/nodeID``; ben's save is refused, merges the file, and
    /// saves again.
    private func mergeThenSave(_ fixture: SaveFixture) async throws -> Saved {
        let url = try fixture.copy()
        let other = try fixture.otherNode(in: url)
        let original = try #require(
            EditableDocument(from: PenParser.parse(contentsOf: url)).nodes[SaveFixture.nodeID]?.common.name
        )
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: url), author: ben, file: url, merger: .threeWay
        )
        try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(SaveFixture.rename("Agent", node: other))
        }
        var unsaved = try [session.submit(.local(LocalEdit(operations: [SaveFixture.rename("Mine")])))]
        guard case let .fileChanged(found, lineage) = try await PenFileTransaction.save(
            session.snapshot(), changes: unsaved, to: url, log: fixture.log
        ) else {
            throw SaveMergeTestFailure.expectedFileChanged
        }
        try unsaved.append(session.submit(.file(found, author: lineage.writer)))
        let snapshot = session.snapshot()
        let outcome = try await PenFileTransaction.save(snapshot, changes: unsaved, to: url, log: fixture.log)
        #expect(outcome == .wrote)
        session.noteSynced(snapshot)
        return Saved(url: url, other: other, original: original, session: session, snapshot: snapshot)
    }

    private enum SaveMergeTestFailure: Error {
        case expectedFileChanged
    }

    private func undo(_ url: URL, log: ActivityLog, as identity: String) async throws -> ActivityUndo.Result {
        try await PenFileTransaction.run(at: url, identity: identity, log: log) { document, recorder in
            try ActivityUndo.reverse(in: document, through: recorder, editing: url, log: log, identity: identity)
        }.value
    }

    private func name(of nodeID: String, in url: URL) throws -> String? {
        try EditableDocument(from: PenParser.parse(contentsOf: url)).nodes[nodeID]?.common.name
    }

    // MARK: - The row

    @Test("a save after a merge that kept local work appends a merge row explaining the file")
    func mergeRowExplainsFile() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let saved = try await mergeThenSave(fixture)

        let rows = try fixture.events(for: saved.url)
        #expect(rows.map(\.op) == [.set, .set, .merge])
        #expect(rows.map(\.identity) == ["claude", "ben", "ben"])
        let merge = try #require(rows.last)
        #expect(merge.revision == saved.snapshot.documentRevision)
        #expect(merge.nodes.contains(saved.other))
        #expect(!merge.inverse.isEmpty)
    }

    @Test("after a merge-then-save, a CLI write finds the log explains the file and records no external row")
    func cliWriteAfterMergeSaveIsQuiet() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let saved = try await mergeThenSave(fixture)

        let outcome = try await PenFileTransaction.run(at: saved.url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(SaveFixture.rename("Again", node: saved.other))
        }

        #expect(!outcome.lineage.isDiverged)
        #expect(try !fixture.events(for: saved.url).contains { $0.op == .external })
    }

    @Test("a save with nothing folded in appends no merge row")
    func noMergeRowWithoutFolding() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: url), author: ben, file: url, merger: .threeWay
        )
        let change = try session.submit(.local(LocalEdit(operations: [SaveFixture.rename("Mine")])))

        try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)

        #expect(try fixture.events(for: url).map(\.op) == [.set])
    }

    // MARK: - Undo across the row

    @Test("undo as ben after a merge-then-save reverses ben's rows and keeps the merged-in values")
    func benUndoKeepsMergedValues() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let saved = try await mergeThenSave(fixture)

        let result = try await undo(saved.url, log: fixture.log, as: "ben")

        #expect(result.undone.map(\.op) == [.set])
        #expect(result.undone.map(\.identity) == ["ben"])
        #expect(try name(of: SaveFixture.nodeID, in: saved.url) == saved.original)
        #expect(try name(of: saved.other, in: saved.url) == "Agent")
    }

    @Test("a second undo as ben does not reverse the same row again")
    func secondBenUndoStops() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let saved = try await mergeThenSave(fixture)
        try await undo(saved.url, log: fixture.log, as: "ben")
        let after = try Data(contentsOf: saved.url)

        let result = try await undo(saved.url, log: fixture.log, as: "ben")

        #expect(result.undone.isEmpty)
        #expect(try Data(contentsOf: saved.url) == after)
    }

    @Test("undo as claude after a merge-then-save is blocked by ben's edit, not by the merge row")
    func claudeUndoBlockedByBen() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let saved = try await mergeThenSave(fixture)

        let result = try await undo(saved.url, log: fixture.log, as: "claude")

        guard case let .blockedByOther(event) = result.stopped else {
            Issue.record("expected blockedByOther, got \(String(describing: result.stopped))")
            return
        }
        #expect(event.identity == "ben")
        #expect(event.op == .set)
    }

    @Test("the undo rule steps over a merge row for every identity")
    func decideStepsOverMerge() {
        let row = ActivityEvent(
            time: Date(), identity: "ben", file: URL(fileURLWithPath: "/tmp/x.pen"), op: .merge,
            nodes: [], paths: [], inverse: [], revision: "r", batch: "b"
        )
        for (identity, all) in [("ben", false), ("claude", false), ("claude", true)] {
            let step = UndoStep.decide(
                row, currentRevision: "other", identity: identity, allIdentities: all, afterUndo: false
            )
            #expect(step == .stepOverMerge)
        }
    }
}
