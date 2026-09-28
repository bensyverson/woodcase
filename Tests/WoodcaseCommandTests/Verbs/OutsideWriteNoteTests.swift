//
//  OutsideWriteNoteTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Drives the built binary against a file somebody rewrote behind the log's back — the
/// case the whole feature exists for: an agent that opened the .pen file with a JSON
/// parser instead of a verb.
///
/// The outside write is made with `python3`'s `json.load`/`json.dump`, deliberately: it
/// is the tool the mistake is actually made with, and going through the library would
/// prove less than it looks.
struct OutsideWriteNoteTests {
    // MARK: - Helpers

    private static let fixtureName = "batch.pen"
    private static let titlePath = "Canvas/Title"

    private enum TestFailure: Error {
        case pythonFailed(String)
    }

    /// A fixture whose .pen file this suite rewrites from outside on purpose.
    private static func fixture() throws -> CommandFixture {
        try CommandFixture(fixture: fixtureName, editedOutsideWoodcase: true)
    }

    /// Rewrites the .pen file with `python3`, the way an agent with a loop would:
    /// `json.load`, change a value, `json.dump`. No lock, no log, no revision.
    ///
    /// - Parameters:
    ///   - url: The .pen file to rewrite.
    ///   - opacity: The opacity to give the document's first top-level node. A property
    ///     rather than a name, so that every address these tests use still resolves and
    ///     the only thing that changed is the document's revision.
    /// - Throws: ``TestFailure/pythonFailed(_:)`` if the interpreter refused.
    private static func rewriteWithPython(_ url: URL, opacity: Double) throws {
        let script = """
        import json, sys
        path = sys.argv[1]
        with open(path) as handle:
            document = json.load(handle)
        document["children"][0]["opacity"] = float(sys.argv[2])
        with open(path, "w") as handle:
            json.dump(document, handle)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script, url.path, String(opacity)]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let message = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        )
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TestFailure.pythonFailed(message) }
    }

    /// The document revision a .pen file holds right now, as a transaction computes it.
    private static func revision(of url: URL) throws -> String {
        try EditableDocument(from: PenParser.parse(contentsOf: url)).documentRevision
    }

    /// Every event in the fixture's own log, oldest first.
    private static func events(in fixture: CommandFixture) throws -> [ActivityEvent] {
        try ActivityReader(log: ActivityLog(home: fixture.home)).read().events
    }

    // MARK: - The note

    @Test("A write after an outside rewrite prints the note once, and the next write is quiet")
    func theNoteFiresOnceAndThenStops() throws {
        let fixture = try Self.fixture()
        let first = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=One", "--as", "ana")
        #expect(first.status == 0)
        #expect(!first.stdout.contains(CommandFixture.outsideWriteNote))
        let known = try #require(Self.events(in: fixture).last)

        try Self.rewriteWithPython(fixture.file, opacity: 0.5)

        let second = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=Two", "--as", "ana")
        #expect(second.status == 0)
        let notes = second.stdoutLines.filter { $0.contains(CommandFixture.outsideWriteNote) }
        #expect(notes.count == 1)
        #expect(notes.first?.hasPrefix("note  ") == true)
        #expect(notes.first?.contains(fixture.file.path) == true)
        #expect(notes.first?.contains(String(known.revision.prefix(8))) == true)
        #expect(notes.first?.contains("the log has no record of that change") == true)
        // The write itself still happened, and still answers as it always does.
        #expect(second.stdoutLines.contains { $0.hasPrefix("document  ") })

        let third = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=Three", "--as", "ana")
        #expect(third.status == 0)
        #expect(!third.stdout.contains(CommandFixture.outsideWriteNote))
        #expect(!third.stderr.contains(CommandFixture.outsideWriteNote))
    }

    @Test("The JSON answer stays one document, so the note goes to stderr there")
    func jsonKeepsItsStreamClean() throws {
        let fixture = try Self.fixture()
        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=One", "--as", "ana")
        try Self.rewriteWithPython(fixture.file, opacity: 0.5)

        let run = try fixture.run(
            "set", fixture.file.path, Self.titlePath, "kind.content=Two", "--as", "ana", "--json"
        )
        #expect(run.status == 0)
        #expect(run.stderr.contains(CommandFixture.outsideWriteNote))
        #expect(!run.stdout.contains(CommandFixture.outsideWriteNote))
        #expect(try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) is [String: Any])
    }

    // MARK: - The row

    @Test("The log gains one external row carrying the revision the file was found at")
    func theLogRecordsWhatWasFound() throws {
        let fixture = try Self.fixture()
        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=One", "--as", "ana")
        try Self.rewriteWithPython(fixture.file, opacity: 0.5)
        let found = try Self.revision(of: fixture.file)

        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=Two", "--as", "ana")

        let events = try Self.events(in: fixture)
        #expect(events.map(\.op) == [.set, .external, .set])
        #expect(events[1].revision == found)
        #expect(events[1].identity == ActivityEvent.unattributed)
        #expect(events[1].inverse.isEmpty)
    }

    @Test("activity renders the external row, naming nobody and no node")
    func activityRendersTheRow() throws {
        let fixture = try Self.fixture()
        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=One", "--as", "ana")
        try Self.rewriteWithPython(fixture.file, opacity: 0.5)
        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=Two", "--as", "ana")

        let run = try fixture.run("activity", fixture.file.path)
        #expect(run.status == 0)
        let row = try #require(run.stdoutLines.first { $0.contains("external") })
        // time | identity | verb | path — nobody wrote it and it touched no node.
        let columns = row.components(separatedBy: " | ")
        #expect(columns.count == 4)
        #expect(columns[1].isEmpty)
        #expect(columns[2].trimmingCharacters(in: .whitespaces) == "external")
        #expect(columns[3] == "-")
    }

    // MARK: - Undo stops there

    @Test("Undo refuses to step past the outside edit, saying when it happened")
    func undoStopsAtTheOutsideEdit() throws {
        let fixture = try Self.fixture()
        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=One", "--as", "ana")
        try Self.rewriteWithPython(fixture.file, opacity: 0.5)
        _ = try fixture.run("set", fixture.file.path, Self.titlePath, "kind.content=Two", "--as", "ana")

        // The first undo reverses the write that came after the outside edit.
        let first = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(first.status == 0)

        // The second meets the row, which has no inverse to replay.
        let second = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(second.status == 3)
        #expect(second.stdout.isEmpty)
        #expect(second.stderr.contains("cannot undo past an edit made outside woodcase at "))

        let row = try #require(Self.events(in: fixture).first { $0.op == .external })
        #expect(second.stderr.contains(ActivityEvent.clockTime(row.time)))
    }
}
