//
//  UndoCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Drives the built binary's `undo` verb against a fixture copy with its own
/// activity log, because the exit code and the sentence on stderr are the contract.
///
/// The events `undo` reverses are produced through the library — a
/// ``PenFileTransaction`` with a recorder — rather than through the other verbs, so
/// these tests do not wait on verbs that are being written alongside this one.
struct UndoCommandTests {
    // MARK: - Fixture helpers

    /// The fixture every test copies: a canvas with a title and two cards.
    private static let fixtureName = "batch.pen"

    /// The title node, and the path `undo` names it by.
    private static let titleID = "Ttl01"
    private static let titlePath = "Canvas/Title"

    /// The frame new nodes are inserted into.
    private static let canvasID = "Cnv01"

    private enum TestFailure: Error {
        case noSuchNode(String)
    }

    /// The `--json` report's shape, spelled out here so a change to it fails a test
    /// rather than silently changing what an agent parses.
    private struct ReportJSON: Codable {
        struct Row: Codable {
            let identity: String
            let nodes: [String]
            let op: String
            let paths: [String]
            let time: String
        }

        let file: String
        let revision: String
        let undone: [Row]
    }

    /// Rewrites the fixture copy in the canonical on-disk form.
    ///
    /// A transaction always writes canonical bytes, so "byte-identical" is only a
    /// meaningful thing to assert about a file that started out canonical. The
    /// repository's fixtures are hand-written and need not be.
    private static func canonicalize(_ url: URL) throws {
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: url))).write(to: url)
    }

    /// Inserts a group node under the canvas, logging one `add` event.
    private static func insert(
        _ id: String, named name: String, into fixture: CommandFixture, as identity: String
    ) async throws {
        let file = fixture.file
        let log = ActivityLog(home: fixture.home)
        try await PenFileTransaction.run(at: file, identity: identity, log: log) { _, recorder in
            try recorder.apply(.insertNode(EditOperation.InsertNode(
                node: PenNode(
                    id: id, common: PenNodeCommon(name: name), kind: .group(PenNode.GroupData())
                ),
                parentID: canvasID
            )))
        }
    }

    /// Renames a node, logging one `set` event.
    private static func rename(
        _ nodeID: String, to name: String, in fixture: CommandFixture, as identity: String
    ) async throws {
        let file = fixture.file
        let log = ActivityLog(home: fixture.home)
        try await PenFileTransaction.run(at: file, identity: identity, log: log) { document, recorder in
            guard var node = document.nodes[nodeID] else { throw TestFailure.noSuchNode(nodeID) }
            node.common.name = name
            try recorder.apply(.updateCommon(
                EditOperation.UpdateCommon(nodeID: nodeID, common: node.common)
            ))
        }
    }

    /// The name a node currently carries on disk.
    private static func name(of nodeID: String, in url: URL) async throws -> String? {
        try await PenFileTransaction.read(at: url) { document in
            document.nodes[nodeID]?.common.name
        }.value
    }

    /// Every event in the fixture's own log, oldest first.
    private static func events(in fixture: CommandFixture) throws -> [ActivityEvent] {
        try ActivityReader(log: ActivityLog(home: fixture.home)).read().events
    }

    // MARK: - Criterion: add then undo restores byte-identical file content

    @Test("An add and its undo leave the file byte for byte as it was")
    func addThenUndoRestoresByteIdenticalContent() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        try await Self.insert("Bdg01", named: "Badge", into: fixture, as: "ana")
        let added = try Data(contentsOf: fixture.file)
        #expect(added != before)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(run.status == 0)
        #expect(try Data(contentsOf: fixture.file) == before)

        // The answer says what was reversed, and where the document now is.
        let lines = run.stdoutLines
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("add  ana  "))
        #expect(lines[0].hasSuffix("  Canvas/Badge"))
        #expect(lines[1].hasPrefix("revision "))
    }

    // MARK: - Criterion: another identity's later edit is a conflict

    @Test("Undo after another identity's later edit on the same node exits 3 and explains")
    func laterEditByAnotherIdentityIsAConflict() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.rename(Self.titleID, to: "Ana", in: fixture, as: "ana")
        try await Self.rename(Self.titleID, to: "Bo", in: fixture, as: "bo")
        let afterBo = try Data(contentsOf: fixture.file)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(run.status == 3)
        #expect(run.stdout.isEmpty)

        // The message names the event, the node path, the identity and the revision
        // that got in the way, and the next command.
        let blocking = try #require(Self.events(in: fixture).last)
        #expect(run.stderr.contains("bo"))
        #expect(run.stderr.contains("set"))
        #expect(run.stderr.contains("Canvas/Bo"))
        #expect(run.stderr.contains(blocking.revision))
        #expect(run.stderr.contains("woodcase activity --file \(fixture.file.path)"))
        #expect(run.stderr.contains("--all"))

        // Refusing means changing nothing.
        #expect(try Data(contentsOf: fixture.file) == afterBo)
        #expect(try Self.events(in: fixture).count == 2)
    }

    @Test("--all undoes another identity's edit")
    func allUndoesAnotherIdentitysEdit() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.rename(Self.titleID, to: "Ana", in: fixture, as: "ana")
        try await Self.rename(Self.titleID, to: "Bo", in: fixture, as: "bo")

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana", "--all")
        #expect(run.status == 0)
        #expect(try await Self.name(of: Self.titleID, in: fixture.file) == "Ana")
        #expect(run.stdoutLines.first?.hasPrefix("set  bo  ") == true)
    }

    // MARK: - Walking back through history

    @Test("A second undo reaches the edit before the one the first undid")
    func twoInvocationsWalkBackThroughHistory() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        try await Self.insert("Bdg01", named: "First", into: fixture, as: "ana")
        try await Self.insert("Bdg02", named: "Second", into: fixture, as: "ana")

        let first = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(first.status == 0)
        #expect(first.stdoutLines.first?.hasSuffix("  Canvas/Second") == true)

        let second = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(second.status == 0)
        #expect(second.stdoutLines.first?.hasSuffix("  Canvas/First") == true)
        #expect(try Data(contentsOf: fixture.file) == before)

        // A third has nothing left: undo does not turn into redo.
        let third = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(third.status == 1)
        #expect(third.stderr.contains("Nothing"))
    }

    @Test("-n reverses several events in one run")
    func countReversesSeveralEvents() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        try await Self.insert("Bdg01", named: "First", into: fixture, as: "ana")
        try await Self.insert("Bdg02", named: "Second", into: fixture, as: "ana")

        let run = try fixture.run("undo", fixture.file.path, "-n", "2", "--as", "ana")
        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 3)
        #expect(run.stdoutLines[0].hasSuffix("  Canvas/Second"))
        #expect(run.stdoutLines[1].hasSuffix("  Canvas/First"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("Stopping short of -n still commits what it reversed and says why")
    func stoppingShortCommitsAndExplains() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.insert("Bdg01", named: "First", into: fixture, as: "ana")
        try await Self.rename(Self.titleID, to: "Bo", in: fixture, as: "bo")
        try await Self.insert("Bdg02", named: "Second", into: fixture, as: "ana")

        let run = try fixture.run("undo", fixture.file.path, "-n", "3", "--as", "ana")
        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 2)
        #expect(run.stdoutLines[0].hasSuffix("  Canvas/Second"))
        #expect(run.stderr.contains("bo"))

        // Bo's rename and ana's first add both survive.
        #expect(try await Self.name(of: Self.titleID, in: fixture.file) == "Bo")
        #expect(try await Self.name(of: "Bdg01", in: fixture.file) == "First")
        #expect(try await Self.name(of: "Bdg02", in: fixture.file) == nil)
    }

    // MARK: - Nothing to undo

    @Test("A file with no recorded edits is a clean negative")
    func nothingRecordedIsACleanNegative() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Nothing to undo"))
        #expect(run.stderr.contains("woodcase activity --file \(fixture.file.path)"))
    }

    // MARK: - Usage

    @Test("Undo without an identity is a usage error naming both ways to give one")
    func missingIdentityIsAUsageError() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.insert("Bdg01", named: "Badge", into: fixture, as: "ana")

        let run = try fixture.run("undo", fixture.file.path)
        #expect(run.status == 2)
        #expect(run.stderr.contains("--as"))
        #expect(run.stderr.contains("WOODCASE_AS"))
    }

    @Test("$WOODCASE_AS supplies the identity when --as is absent")
    func environmentSuppliesTheIdentity() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.insert("Bdg01", named: "Badge", into: fixture, as: "ana")

        let run = try fixture.run(
            ["undo", fixture.file.path], environment: [Identity.environmentVariable: "ana"]
        )
        #expect(run.status == 0)
    }

    @Test("A count below one is a usage error")
    func countBelowOneIsAUsageError() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let run = try fixture.run("undo", fixture.file.path, "-n", "0", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("-n"))
    }

    @Test("A missing file is a target failure")
    func missingFileIsATargetFailure() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let missing = fixture.root.appendingPathComponent("nope.pen").path
        let run = try fixture.run("undo", missing, "--as", "ana")
        #expect(run.status == 4)
        #expect(run.stderr.contains("no such file"))
    }

    // MARK: - The machine form

    @Test("--json reports the events reversed and the revision left behind")
    func jsonReportsWhatWasUndone() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.insert("Bdg01", named: "Badge", into: fixture, as: "ana")

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana", "--json")
        #expect(run.status == 0)

        let report = try JSONDecoder().decode(ReportJSON.self, from: Data(run.stdout.utf8))
        #expect(report.file == ActivityEvent.canonicalPath(for: fixture.file))
        #expect(report.undone.count == 1)
        #expect(report.undone[0].identity == "ana")
        #expect(report.undone[0].op == "add")
        #expect(report.undone[0].nodes == ["Bdg01", Self.canvasID])
        #expect(report.undone[0].paths == ["Canvas/Badge", "Canvas"])
        #expect(!report.undone[0].time.isEmpty)

        let settled = try await PenFileTransaction.read(at: fixture.file) { $0.documentRevision }
        #expect(report.revision == settled.value)
    }

    // MARK: - The undo is itself logged

    @Test("Reversing an event appends undo events attributed to whoever ran it")
    func undoIsItselfRecorded() async throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try await Self.rename(Self.titleID, to: "Ana", in: fixture, as: "ana")

        let run = try fixture.run("undo", fixture.file.path, "--as", "bo", "--all")
        #expect(run.status == 0)

        let events = try Self.events(in: fixture)
        #expect(events.count == 2)
        #expect(events[1].op == .undo)
        #expect(events[1].identity == "bo")
        #expect(events[1].nodes == [Self.titleID])
        #expect(events[1].paths == [Self.titlePath])
    }
}
