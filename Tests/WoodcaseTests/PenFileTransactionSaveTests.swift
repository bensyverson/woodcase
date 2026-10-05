//
//  PenFileTransactionSaveTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An app saves its session's changes through ``PenFileTransaction/save(_:changes:to:log:timeout:)``:
/// under the lock, in the CLI's bytes, with its rows in the log under its own identity.
struct PenFileTransactionSaveTests {
    private static let nodeID = "jSUCH"
    private let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))

    private static func rename(_ name: String, node: String = nodeID) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: node, properties: ["common.name": .string(name)]))
    }

    private func openSession(_ url: URL) throws -> DocumentSession {
        try DocumentSession(document: PenParser.parse(contentsOf: url), author: ben, file: url, merger: .threeWay)
    }

    /// A second node of the fixture to edit beside ``nodeID``.
    private func otherNode(in url: URL) throws -> String {
        let document = try EditableDocument(from: PenParser.parse(contentsOf: url))
        return try #require(document.nodes.keys.sorted().first { $0 != Self.nodeID })
    }

    // MARK: - The contract Penumbra checks

    @Test("a saved change is logged under the app's identity, with its node ids")
    func savedChangeIsLoggedUnderIdentity() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Saved")])))
        let snapshot = session.snapshot()

        let outcome = try await PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)

        #expect(outcome == .wrote)
        let rows = try fixture.events(for: url)
        let row = try #require(rows.last)
        #expect(rows.count == 1)
        #expect(row.identity == "ben")
        #expect(row.nodes == [Self.nodeID])
        #expect(row.op == .set)
        #expect(row.revision == snapshot.documentRevision)
        #expect(!row.inverse.isEmpty)
    }

    @Test("a save writes the same bytes the CLI writes for the same document")
    func saveWritesCLIBytes() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let appFile = try fixture.copy(named: "app.pen")
        let cliFile = try fixture.copy(named: "cli.pen")
        let session = try openSession(appFile)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Same")])))

        try await PenFileTransaction.save(session.snapshot(), changes: [change], to: appFile, log: fixture.log)
        try await PenFileTransaction.run(at: cliFile, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(Self.rename("Same"))
        }

        #expect(try Data(contentsOf: appFile) == Data(contentsOf: cliFile))
    }

    // MARK: - Agents after the save

    @Test("after a save, the CLI finds the log explains the file and records no external row")
    func logExplainsSavedFile() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Saved")])))
        try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)

        let other = try otherNode(in: url)
        let outcome = try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(Self.rename("Agent", node: other))
        }

        #expect(!outcome.lineage.isDiverged)
        #expect(try fixture.events(for: url).map(\.op) == [.set, .set])
    }

    @Test("an agent's undo of the app's saved change reverses it instead of stopping at an outside edit")
    func agentUndoesAppSave() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let before = try Data(contentsOf: url)
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Saved")])))
        try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)

        let result = try await PenFileTransaction.run(at: url, identity: "ben", log: fixture.log) { document, recorder in
            try ActivityUndo.reverse(in: document, through: recorder, editing: url, log: fixture.log, identity: "ben")
        }.value

        #expect(result.undone.map(\.identity) == ["ben"])
        #expect(result.stopped == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("an agent's undo of its own edit after the app's save is not blocked")
    func agentUndoAfterAppSave() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Saved")])))
        try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)
        let saved = try Data(contentsOf: url)
        let other = try otherNode(in: url)
        try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(Self.rename("Agent", node: other))
        }

        let result = try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { document, recorder in
            try ActivityUndo.reverse(in: document, through: recorder, editing: url, log: fixture.log, identity: "claude")
        }.value

        #expect(result.undone.count == 1)
        #expect(result.stopped == nil)
        #expect(try Data(contentsOf: url) == saved)
        // No external row anywhere: the log explained every write, the app's included.
        let rows = try fixture.events(for: url)
        #expect(rows.map(\.identity) == ["ben", "claude", "claude"])
        #expect(rows.map(\.op) == [.set, .set, .undo])
    }

    // MARK: - Coexisting with other writers

    @Test("a save refuses, writing nothing, when the file changed since the session last synced")
    func saveRefusesChangedFile() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let other = try otherNode(in: url)
        try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(Self.rename("Agent", node: other))
        }
        let agentBytes = try Data(contentsOf: url)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Mine")])))

        let outcome = try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)

        guard case let .fileChanged(found, lineage) = outcome else {
            Issue.record("expected fileChanged, got \(outcome)")
            return
        }
        #expect(try found == (PenParser.parse(contentsOf: url)))
        #expect(lineage.newest?.identity == "claude")
        #expect(!lineage.isDiverged)
        #expect(try Data(contentsOf: url) == agentBytes)
        #expect(try fixture.events(for: url).map(\.identity) == ["claude"])
    }

    @Test("after a refused save, merging the file and saving again keeps both edits")
    func mergeThenSave() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let other = try otherNode(in: url)
        try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(Self.rename("Agent", node: other))
        }
        var unsaved = try [session.submit(.local(LocalEdit(operations: [Self.rename("Mine")])))]
        guard case let .fileChanged(found, lineage) = try await PenFileTransaction.save(
            session.snapshot(), changes: unsaved, to: url, log: fixture.log
        ) else {
            Issue.record("expected fileChanged")
            return
        }

        try unsaved.append(session.submit(.file(found, author: lineage.writer)))
        let snapshot = session.snapshot()
        let outcome = try await PenFileTransaction.save(snapshot, changes: unsaved, to: url, log: fixture.log)
        session.noteSynced(snapshot)

        #expect(outcome == .wrote)
        let written = try EditableDocument(from: PenParser.parse(contentsOf: url))
        #expect(written.nodes[Self.nodeID]?.common.name == "Mine")
        #expect(written.nodes[other]?.common.name == "Agent")
        // ben's row, then the merge row that explains the file holding claude's work too.
        #expect(try fixture.events(for: url).map(\.identity) == ["claude", "ben", "ben"])
        #expect(!session.hasUnsyncedChanges)
    }

    @Test("a session told of each save keeps saving without refusals")
    func successiveSaves() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)

        for name in ["One", "Two", "Three"] {
            let change = try session.submit(.local(LocalEdit(operations: [Self.rename(name)])))
            let snapshot = session.snapshot()
            let outcome = try await PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)
            #expect(outcome == .wrote)
            session.noteSynced(snapshot)
        }

        #expect(try fixture.events(for: url).count == 3)
        #expect(try EditableDocument(from: PenParser.parse(contentsOf: url)).nodes[Self.nodeID]?.common.name == "Three")
    }

    @Test("a save logs only the changes its snapshot includes")
    func saveLogsOnlyIncludedChanges() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let first = try session.submit(.local(LocalEdit(operations: [Self.rename("First")])))
        let snapshot = session.snapshot()
        let later = try session.submit(.local(LocalEdit(operations: [Self.rename("Later")])))

        try await PenFileTransaction.save(snapshot, changes: [first, later], to: url, log: fixture.log)

        let rows = try fixture.events(for: url)
        #expect(rows.count == 1)
        #expect(rows.first?.revision == snapshot.documentRevision)
    }

    @Test("a save whose document the file already holds writes and logs nothing")
    func unchangedSaveWritesNothing() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let changes = try [
            session.submit(.local(LocalEdit(operations: [Self.rename("Away")]))),
            session.submit(.local(LocalEdit(operations: [Self.rename("Child")]))),
        ]
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let original = try EditableDocument(from: PenParser.parse(contentsOf: url)).nodes[Self.nodeID]?.common.name
        try session.submit(.local(LocalEdit(operations: [Self.rename(#require(original))])))

        let outcome = try await PenFileTransaction.save(session.snapshot(), changes: changes, to: url, log: fixture.log)

        #expect(outcome == .unchanged)
        #expect(outcome.isSynced)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == modified)
        #expect(try fixture.events(for: url).isEmpty)
    }

    @Test("a save records an external row first when the log does not explain the file it opened")
    func saveRecordsExternalRow() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let other = try otherNode(in: url)
        try await PenFileTransaction.run(at: url, identity: "claude", log: fixture.log) { _, recorder in
            try recorder.apply(Self.rename("Agent", node: other))
        }
        // An outside writer: no lock, no log.
        let outside = try EditableDocument(from: PenParser.parse(contentsOf: url))
        try outside.apply(Self.rename("Outside", node: other))
        try PenParser.encodeForFile(outside.materialize()).write(to: url)
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Mine")])))

        let outcome = try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)

        #expect(outcome == .wrote)
        #expect(try fixture.events(for: url).map(\.op) == [.set, .external, .set])
        #expect(try fixture.events(for: url).last?.identity == "ben")
    }

    @Test("a save from a session that never knew its file's contents throws fileStateUnknown")
    func unknownFileStateThrows() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let before = try Data(contentsOf: url)
        let session = try DocumentSession(
            editing: EditableDocument(from: PenParser.parse(contentsOf: url)), author: ben, file: url
        )
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Mine")])))

        await #expect(throws: SessionError.fileStateUnknown) {
            try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url, log: fixture.log)
        }
        #expect(try Data(contentsOf: url) == before)
    }
}
