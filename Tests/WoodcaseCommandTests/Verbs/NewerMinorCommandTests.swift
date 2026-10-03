//
//  NewerMinorCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A file written by a newer Pen of the same major — 2.21 while this build models 2.20.
///
/// It reads with one notice, lints clean when the design is clean, and every write verb
/// writes it back as 2.21: stamping the model's older version over it would make the
/// next Pen to open it migrate data this build never touched.
@Suite("A newer-minor .pen file")
struct NewerMinorCommandTests {
    /// The version the fixtures are rewritten to declare.
    static let newer = "2.21"

    /// A write verb, its arguments after the file, and any file it reads its body from.
    struct WriteCase: CustomTestStringConvertible {
        /// The verb, with its subcommand when it has one (`vars set`).
        let verb: [String]
        let arguments: [String]
        let body: (name: String, text: String)?

        init(verb: String..., arguments: [String], body: (name: String, text: String)? = nil) {
            self.verb = verb
            self.arguments = arguments
            self.body = body
        }

        var testDescription: String {
            verb.joined(separator: " ")
        }

        /// The whole command line against `file`, attributed.
        func commandLine(on file: URL) -> [String] {
            verb + [file.path] + arguments + ["--as", "ana"]
        }

        /// Writes the body file, if the verb reads one, beside the fixture.
        func writeBody(into fixture: CommandFixture) throws {
            guard let body else { return }
            try Data(body.text.utf8).write(to: fixture.root.appendingPathComponent(body.name))
        }
    }

    static let writes: [WriteCase] = [
        WriteCase(verb: "set", arguments: ["Canvas/Title", "kind.content=Hello"]),
        WriteCase(verb: "cp", arguments: ["Canvas/Cards/First", "Board"]),
        WriteCase(verb: "mv", arguments: ["Canvas/Title", "Board"]),
        WriteCase(verb: "rm", arguments: ["Canvas/Cards/First"]),
        WriteCase(
            verb: "add", arguments: ["Canvas", "-F", "subtree.json"],
            body: ("subtree.json", #"{"type":"frame","name":"Hero","width":10,"height":10}"#)
        ),
        WriteCase(
            verb: "apply", arguments: ["-F", "ops.jsonl"],
            body: ("ops.jsonl", #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"}}"#)
        ),
        WriteCase(
            verb: "js", arguments: ["-F", "edit.js"],
            body: ("edit.js", "doc.set('Canvas/Title', { 'kind.content': 'Hello' });")
        ),
        WriteCase(verb: "vars", "set", arguments: ["gap=8"]),
    ]

    /// Copies `batch.pen` and rewrites its declared version.
    static func fixture(declaring version: String) throws -> CommandFixture {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let text = try String(contentsOf: fixture.file, encoding: .utf8)
        let rewritten = text.replacingOccurrences(of: #""version": "2.17""#, with: #""version": "\#(version)""#)
        #expect(rewritten != text, "batch.pen no longer declares 2.17; update this helper")
        try rewritten.write(to: fixture.file, atomically: true, encoding: .utf8)
        return fixture
    }

    /// The `version` the file on disk declares.
    static func declaredVersion(of url: URL) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["version"] as? String
    }

    // MARK: - Writes

    @Test("Every write verb writes the declared version back", arguments: writes)
    func writeKeepsTheDeclaredVersion(_ write: WriteCase) throws {
        let fixture = try Self.fixture(declaring: Self.newer)
        try write.writeBody(into: fixture)

        let run = try fixture.run(write.commandLine(on: fixture.file))

        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Self.declaredVersion(of: fixture.file) == Self.newer)
    }

    @Test("undo writes the declared version back")
    func undoKeepsTheDeclaredVersion() throws {
        let fixture = try Self.fixture(declaring: Self.newer)
        #expect(try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Hi", "--as", "ana").status == 0)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Self.declaredVersion(of: fixture.file) == Self.newer)
    }

    @Test("migrate leaves a newer minor alone, as already current")
    func migrateSkipsANewerMinor() throws {
        let fixture = try Self.fixture(declaring: Self.newer)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("migrate", fixture.file.path)

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("skipped 1"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - Reads

    @Test("lint exits 0 on a clean newer-minor file")
    func lintIsCleanOnANewerMinor() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let clean = fixture.root.appendingPathComponent("clean.pen")
        try Data(#"""
        {"version": "\#(Self.newer)", "children": [{"id": "Box01", "name": "Box", "type": "frame", "x": 0, "y": 0, "width": 10, "height": 10}]}
        """#.utf8).write(to: clean)

        let run = try fixture.run("lint", clean.path)

        #expect(run.status == 0, "\(run.stdout)\(run.stderr)")
        #expect(run.stdout.isEmpty)
    }

    @Test("lint --severity notice shows the notice and still exits 0")
    func lintShowsTheNoticeOnRequest() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let clean = fixture.root.appendingPathComponent("clean.pen")
        try Data(#"""
        {"version": "\#(Self.newer)", "children": [{"id": "Box01", "name": "Box", "type": "frame", "x": 0, "y": 0, "width": 10, "height": 10}]}
        """#.utf8).write(to: clean)

        let run = try fixture.run("lint", clean.path, "--severity", "notice")

        #expect(run.status == 0, "\(run.stdout)\(run.stderr)")
        #expect(run.stdout.hasPrefix("notice pipeline"))
        #expect(run.stdout.contains(Self.newer))
    }

    @Test("tree reads a newer minor and says so on stderr")
    func treeNamesTheNewerMinor() throws {
        let fixture = try Self.fixture(declaring: Self.newer)

        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("Canvas"))
        #expect(run.stderr.contains("notice: [migration]"))
        #expect(run.stderr.contains(Self.newer))
    }

    @Test("render --strict does not fail on the notice")
    func strictRenderIgnoresTheNotice() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let clean = fixture.root.appendingPathComponent("clean.pen")
        try Data(#"""
        {"version": "\#(Self.newer)", "children": [{"id": "Box01", "name": "Box", "type": "frame", "x": 0, "y": 0, "width": 10, "height": 10, "fill": "#FF0000"}]}
        """#.utf8).write(to: clean)

        let run = try fixture.run("render", clean.path, "--strict", "--output-dir", fixture.root.path)

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stderr.contains("notice: [migration]"))
    }
}
