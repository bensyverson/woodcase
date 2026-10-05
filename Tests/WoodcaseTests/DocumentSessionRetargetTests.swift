//
//  DocumentSessionRetargetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A session follows its document to a new file — a first save, a rename, a move —
/// with ``DocumentSession/retarget(to:)``, and keeps its undo and redo history.
struct DocumentSessionRetargetTests {
    private static let nodeID = "jSUCH"
    private let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))

    private static func rename(_ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": .string(name)]))
    }

    /// Two repositories side by side, each with its own activity log.
    private struct Scratch {
        let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DocumentSessionRetargetTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            for repository in ["one", "two"] {
                try FileManager.default.createDirectory(
                    at: directory.appendingPathComponent("\(repository)/.git"), withIntermediateDirectories: true
                )
            }
        }

        func url(_ path: String) -> URL {
            directory.appendingPathComponent(path)
        }

        /// A canonical copy of the `layout-vertical` fixture at `path`.
        func fixture(at path: String) throws -> URL {
            let source = try #require(Bundle.module.url(
                forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
            ))
            let url = url(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: source))).write(to: url)
            return url
        }

        /// The log a file resolves to, ignoring this process's `$WOODCASE_HOME`.
        func log(for url: URL) -> ActivityLog {
            ActivityLogLocation.log(for: url, environment: [:])
        }

        func rows(for url: URL) throws -> [ActivityEvent] {
            try ActivityReader(log: log(for: url)).read(file: url).events
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Saves everything unsaved and reports it synced, as an app does.
    private func save(_ session: DocumentSession, _ unsaved: inout [CommittedChange], to url: URL, log: ActivityLog) async throws {
        let snapshot = session.snapshot()
        let outcome = try await PenFileTransaction.save(snapshot, changes: unsaved, to: url, log: log)
        #expect(outcome.isSynced)
        session.noteSynced(snapshot)
        unsaved.removeAll { $0.sequence <= snapshot.sequence }
    }

    private func name(in url: URL) throws -> String? {
        try EditableDocument(from: PenParser.parse(contentsOf: url)).nodes[Self.nodeID]?.common.name
    }

    // MARK: - History survives

    @Test("after a rename, undo and redo still work and log under the new file")
    func undoAndRedoSurviveARename() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let before = try scratch.fixture(at: "one/Before.pen")
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: before), author: ben, file: before, merger: .threeWay
        )
        var unsaved = try [
            session.submit(.local(LocalEdit(operations: [Self.rename("First")]))),
            session.submit(.local(LocalEdit(operations: [Self.rename("Second")]))),
        ]
        try unsaved.append(session.submit(.undo))
        try await save(session, &unsaved, to: before, log: scratch.log(for: before))

        let after = scratch.url("one/After.pen")
        try FileManager.default.moveItem(at: before, to: after)
        session.retarget(to: after)

        #expect(session.file == after)
        #expect(session.canUndo)
        #expect(session.canRedo)
        try unsaved.append(session.submit(.redo))
        try unsaved.append(session.submit(.undo))
        try unsaved.append(session.submit(.undo))
        try await save(session, &unsaved, to: after, log: scratch.log(for: after))

        let rows = try scratch.rows(for: after)
        #expect(rows.map(\.op) == [.redo, .undo, .undo])
        #expect(rows.allSatisfy { $0.file == ActivityEvent.canonicalPath(for: after) })
        #expect(try name(in: after) != "First")
        #expect(try name(in: after) != "Second")
        #expect(!session.canUndo)
    }

    @Test("retargeting keeps what the session knows of its file")
    func retargetKeepsTheSyncedState() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let before = try scratch.fixture(at: "one/Before.pen")
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: before), author: ben, file: before, merger: .threeWay
        )
        try session.submit(.local(LocalEdit(operations: [Self.rename("Unsaved")])))
        let synced = session.syncedRevision
        let sequence = session.syncedSequence

        session.retarget(to: scratch.url("two/After.pen"))

        #expect(session.file == scratch.url("two/After.pen"))
        #expect(session.syncedRevision == synced)
        #expect(session.syncedSequence == sequence)
        #expect(session.hasUnsyncedChanges)
    }

    // MARK: - Across activity-log roots

    @Test("a move across log roots starts the file's rows in the new log; the old log keeps its own")
    func moveAcrossLogRoots() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let before = try scratch.fixture(at: "one/Design.pen")
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: before), author: ben, file: before, merger: .threeWay
        )
        var unsaved = try [session.submit(.local(LocalEdit(operations: [Self.rename("Saved there")])))]
        try await save(session, &unsaved, to: before, log: scratch.log(for: before))
        // Made before the move, saved after it.
        try unsaved.append(session.submit(.local(LocalEdit(operations: [Self.rename("Carried")]))))

        let after = scratch.url("two/Design.pen")
        try FileManager.default.moveItem(at: before, to: after)
        session.retarget(to: after)
        try unsaved.append(session.submit(.local(LocalEdit(operations: [Self.rename("Moved")]))))
        try await save(session, &unsaved, to: after, log: scratch.log(for: after))

        #expect(scratch.log(for: before).fileURL != scratch.log(for: after).fileURL)
        #expect(try scratch.rows(for: before).map(\.op) == [.set])
        let moved = try scratch.rows(for: after)
        #expect(moved.map(\.op) == [.set, .set])
        #expect(moved.allSatisfy { $0.file == ActivityEvent.canonicalPath(for: after) })
        #expect(!moved.contains { $0.op == .external })
        // The CLI finds the new log explains the file.
        let found = try EditableDocument(from: PenParser.parse(contentsOf: after)).documentRevision
        #expect(try LogLineage.read(after, at: found, from: scratch.log(for: after)).isDiverged == false)
        #expect(try name(in: after) == "Moved")
        // And undo reaches back past the move, to the edit saved before it.
        try unsaved.append(session.submit(.undo))
        try unsaved.append(session.submit(.undo))
        try unsaved.append(session.submit(.undo))
        try await save(session, &unsaved, to: after, log: scratch.log(for: after))
        #expect(try scratch.rows(for: after).map(\.op) == [.set, .set, .undo, .undo, .undo])
    }

    @Test("a renamed bundle keeps one log, and undo reaches back across the rename")
    func bundleRenameKeepsOneLog() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let before = scratch.url("one/Before.umbra")
        try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
        let inner = try scratch.fixture(at: "one/Before.umbra/document.pen")
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: inner), author: ben, file: before, merger: .threeWay
        )
        var unsaved = try [session.submit(.local(LocalEdit(operations: [Self.rename("Bundled")])))]
        try await save(session, &unsaved, to: before, log: scratch.log(for: before))

        let after = scratch.url("one/After.umbra")
        try FileManager.default.moveItem(at: before, to: after)
        session.retarget(to: after)
        try unsaved.append(session.submit(.undo))
        try await save(session, &unsaved, to: after, log: scratch.log(for: after))

        #expect(try scratch.rows(for: after).map(\.op) == [.set, .undo])
    }

    // MARK: - First save

    @Test("an untitled session's first save creates the file with a `new` row, and keeps its history")
    func firstSaveOfAnUntitledSession() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let template = try PenParser.parse(contentsOf: scratch.fixture(at: "template.pen"))
        let session = DocumentSession(document: template, author: ben, merger: .threeWay)
        try session.submit(.local(LocalEdit(operations: [Self.rename("Before saving")])))
        #expect(session.file == nil)

        let url = scratch.url("one/Untitled.pen")
        let snapshot = session.snapshot()
        try await PenFileTransaction.create(
            at: url, document: snapshot.document, identity: ben.name, log: scratch.log(for: url)
        )
        session.retarget(to: url)
        session.noteSynced(snapshot)
        var unsaved = try [session.submit(.undo)]
        try await save(session, &unsaved, to: url, log: scratch.log(for: url))

        #expect(try scratch.rows(for: url).map(\.op) == [.new, .undo])
        #expect(try name(in: url) == EditableDocument(from: template).nodes[Self.nodeID]?.common.name)
    }
}
