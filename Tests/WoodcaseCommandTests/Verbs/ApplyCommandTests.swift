//
//  ApplyCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Drives the built binary, per the house rule: exit code, stdout and stderr are what
/// an agent sees, and only a real process produces all three faithfully.
@MainActor
@Suite("apply")
struct ApplyCommandTests {
    // MARK: - Helpers

    private func document(at url: URL) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// The literal `content` of a text node, or `nil` if it is not text.
    private func text(_ nodeID: String, in document: EditableDocument) -> String? {
        guard case let .text(data) = document.node(id: nodeID)?.kind else { return nil }
        return data.content?.literalValue
    }

    private func writeOps(_ jsonl: String, into fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent("ops.jsonl")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - Mixed batches

    @Test("A mixed batch exits 1 with per-line statuses and the file holds the applied ops")
    func mixedBatchExitsOne() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        {"op":"set","target":"Canvas/Cards/Second","props":{"common.name":"After"}}
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 1)
        #expect(run.stdoutLines.count == 4)
        #expect(run.stdoutLines[0].hasPrefix("line 0  applied"))
        #expect(run.stdoutLines[1].hasPrefix("line 1  failed"))
        #expect(run.stdoutLines[2].hasPrefix("line 2  applied"))
        #expect(run.stdoutLines[3].contains("2 applied, 1 failed, 0 cascaded"))

        let doc = try document(at: fixture.file)
        #expect(text("Ttl01", in: doc) == "Before")
        #expect(doc.node(id: "Cd201")?.common.name == "After")
        #expect(doc.node(id: "Cd101")?.common.name == "First")
    }

    @Test("--atomic discards everything on any failure and writes nothing")
    func atomicDiscardsEverything() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try String(contentsOf: fixture.file, encoding: .utf8)
        let opsPath = try writeOps("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--atomic")

        #expect(run.status == 1)
        #expect(run.stdoutLines[0].hasPrefix("line 0  cascaded"))
        #expect(run.stdoutLines[1].hasPrefix("line 1  failed"))
        #expect(run.stdoutLines[2].contains("0 applied, 1 failed, 1 cascaded"))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == before)
    }

    // MARK: - Conflicts

    @Test("A stale revision exits 3")
    func staleRevisionExitsThree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Nope"},"rev":"0000000000000000"}"#,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdoutLines[0].hasPrefix("line 0  failed"))
    }

    // MARK: - Malformed batches

    @Test("A malformed batch line exits 2, naming the line, and touches nothing")
    func malformedLineExitsTwo() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try String(contentsOf: fixture.file, encoding: .utf8)
        let opsPath = try writeOps("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        not json
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("line 2"))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == before)
    }

    @Test("A malformed batch line's remedy states the grammar, not just where to find it")
    func malformedLineStatesTheGrammar() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        not json
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("one JSON object per line"))
        #expect(run.stderr.contains("\"op\""))
    }

    @Test("A line that is a fragment of a pretty-printed multi-line object says one op per line")
    func multiLineFragmentNamesTheRule() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try String(contentsOf: fixture.file, encoding: .utf8)
        let opsPath = try writeOps("""
        {
          "op": "set",
          "target": "Canvas/Title",
          "props": {"kind.content": "Hi"}
        }
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("line 1"))
        #expect(run.stderr.contains("one op per line"))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == before)
    }

    @Test("A lone closing brace is named as a fragment too")
    func loneClosingBraceIsAFragment() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        }
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("line 2"))
        #expect(run.stderr.contains("one op per line"))
    }

    // MARK: - Retry

    @Test("--retry re-runs only the failed and cascaded lines, leaving applied ones untouched")
    func retryReRunsOnlyFailedLines() async throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsURL = fixture.root.appendingPathComponent("ops.jsonl")
        try """
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"First pass"}}
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","width":10},"tag":"hero"}
        {"op":"set","target":"@hero","props":{"common.name":"Hero"}}
        """.write(to: opsURL, atomically: true, encoding: .utf8)

        let firstRun = try fixture.run("apply", fixture.file.path, "-F", opsURL.path, "--json")
        #expect(firstRun.status == 1)

        let reportURL = fixture.root.appendingPathComponent("report.json")
        try firstRun.stdout.write(to: reportURL, atomically: true, encoding: .utf8)

        // Somebody edits the already-applied line's target between runs: a retry that
        // touched a line that already applied would clobber this. It goes through a
        // recorder, unattributed, like any other write — an edit applied straight to
        // the document would leave the activity log unable to account for the file, and
        // the next write would (rightly) print the outside-write note.
        try await PenFileTransaction.run(
            at: fixture.file, identity: nil, log: ActivityLog(home: fixture.home)
        ) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Ttl01", properties: ["kind.content": .string("edited between runs")]
            )))
        }

        // Fix the unnamed node and retry.
        try """
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"First pass"}}
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10},"tag":"hero"}
        {"op":"set","target":"@hero","props":{"common.name":"Hero"}}
        """.write(to: opsURL, atomically: true, encoding: .utf8)

        let secondRun = try fixture.run(
            "apply", fixture.file.path, "-F", opsURL.path, "--retry", reportURL.path
        )

        #expect(secondRun.status == 0)
        #expect(secondRun.stdoutLines[0].hasPrefix("line 0  applied"))
        #expect(secondRun.stdoutLines[1].hasPrefix("line 1  applied"))
        #expect(secondRun.stdoutLines[2].hasPrefix("line 2  applied"))

        let doc = try document(at: fixture.file)
        #expect(text("Ttl01", in: doc) == "edited between runs")
        #expect(doc.node(id: "Cd101")?.common.name == "First")
    }

    // MARK: - Standard input

    @Test("-F - reads the batch from standard input")
    func readsBatchFromStandardInput() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let process = Process()
        process.executableURL = try CommandFixture.binary()
        process.arguments = ["apply", fixture.file.path, "-F", "-"]
        process.currentDirectoryURL = fixture.root

        var environment = ProcessInfo.processInfo.environment
        environment[ActivityLog.homeEnvironmentVariable] = fixture.home.path
        environment["HOME"] = fixture.root.path
        environment.removeValue(forKey: Identity.environmentVariable)
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        stdin.fileHandleForWriting.write(Data(
            #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"From stdin"}}"#.utf8
        ))
        try stdin.fileHandleForWriting.close()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(String(decoding: stdoutData, as: UTF8.self).contains("line 0  applied"))

        let doc = try document(at: fixture.file)
        #expect(text("Ttl01", in: doc) == "From stdin")
    }

    // MARK: - The divergence echo

    @Test("A set op whose content resolves as a defined variable echoes under its own line")
    func contentVariableWarns() throws {
        let fixture = try CommandFixture(fixture: "content-variable.pen")
        let opsPath = try writeOps("""
        {"op":"set","target":"Title","props":{"kind.content":"$v-muted"}}
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 0)
        #expect(run.stdoutLines[0] == "line 0  applied  Title")
        #expect(run.stdoutLines[1] == "        kind.content resolved $v-muted as a reference to "
            + "the color variable v-muted — write \\$v-muted for the literal")
        #expect(run.stderr.isEmpty)
    }

    @Test("An escaped content literal in a batch stores without an echo")
    func escapedContentDoesNotWarn() throws {
        let fixture = try CommandFixture(fixture: "content-variable.pen")
        let opsPath = try writeOps(#"{"op":"set","target":"Title","props":{"kind.content":"\\$v-muted"}}"#, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 0)
        #expect(!run.stdout.contains("resolved"))
        #expect(!run.stderr.contains("resolved"))
    }

    @Test("--json carries the post-state node for every applied line")
    func jsonCarriesPostStateNodes() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"One"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Primero"}}
        """, into: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(BatchReport.self, from: Data(run.stdout.utf8))
        #expect(report.lines.map(\.id) == ["Ttl01", "Cd101"])
        #expect(report.lines.compactMap(\.node).count == 2)
        #expect(report.lines[1].node?.common.name == "Primero")
    }

    // MARK: - Help

    @Test("apply --help prints the batch grammar")
    func helpPrintsGrammar() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("apply", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("A batch is JSONL"))
        #expect(run.stdout.contains(#"{"op":"set","target":ADDR"#))
    }
}
