//
//  DryRunOutsideTheApplierTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The five write verbs that do not go through ``Woodcase/BatchApplier`` — `vars set`,
/// `vars rm`, `vars axis add`, `undo` and `new` — under `--dry-run`.
///
/// `DryRunTests` pins the contract for the eight verbs that share ``WriteReport``. These
/// five each answer with a report of their own, so the contract has to be pinned once
/// per shape: the marker leads standard output, `--json` carries `"dryRun": true`, no
/// revision is printed because none was made, and the file and the activity log are what
/// they were. They are here rather than in `DryRunTests` because three of them need a
/// fixture that suite's table cannot give them — a document with variables, a log with an
/// edit in it, and a path that does not exist yet.
@Suite("woodcase --dry-run outside the applier")
struct DryRunOutsideTheApplierTests {
    // MARK: - The verbs under test

    /// One write verb, as the argv that follows the program name.
    ///
    /// `@file` stands for the fixture copy; `@fresh` for a file name that does not exist
    /// yet, written relative to the fixture's own directory so two runs in two fixtures
    /// print the same path.
    struct Verb: CustomStringConvertible {
        /// The verb's name, which is also this case's label in the test output.
        let name: String

        /// The command line, with placeholders for the fixture's paths.
        let argv: [String]

        var description: String {
            name
        }
    }

    /// The four that run against a document with variables in it.
    ///
    /// `undo` is not here: it needs an activity log with an edit in it, which every one
    /// of these tests asserts the absence of.
    static let verbs: [Verb] = [
        Verb(name: "vars set", argv: ["vars", "set", "@file", "brand=#FF6600"]),
        Verb(name: "vars rm", argv: ["vars", "rm", "@file", "showSubtitle"]),
        Verb(name: "vars axis add", argv: ["vars", "axis", "add", "@file", "mode=light,dark"]),
        Verb(name: "new", argv: ["new", "@fresh"]),
    ]

    /// The fixture the table runs against: four variables, one of which two nodes'
    /// properties resolve through.
    private static let fixtureName = "parser-variables.pen"

    // MARK: - Helpers

    /// A verb's argv with the fixture's own paths substituted in.
    private static func argv(_ verb: Verb, in fixture: CommandFixture) -> [String] {
        verb.argv.map { argument in
            switch argument {
            case "@file": fixture.file.path
            case "@fresh": freshName
            default: argument
            }
        }
    }

    /// The name `new` is pointed at — relative, so it is the same bytes in the answer
    /// whichever temporary directory the fixture made.
    private static let freshName = "fresh.pen"

    /// A real write's answer with every revision row taken out of it.
    ///
    /// `vars` and `undo` print `revision <hash>`; `new` prints `document  <hash>`.
    private static func withoutRevisions(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("revision ") && !$0.hasPrefix("document  ") }
            .map(String.init)
    }

    /// The output with wire timestamps blanked, for `undo`'s rows.
    private static func maskingTimes(_ output: String) -> String {
        output.replacing(/\d{4}-\d{2}-\d{2}T[\d:.]+Z/) { _ in "<time>" }
    }

    /// The decoded `--json` object a run printed.
    private static func json(_ run: CommandRun) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any])
    }

    /// A fixture with one recorded `set` in its activity log, for `undo` to reverse.
    private static func seeded() throws -> CommandFixture {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let seed = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"
        )
        #expect(seed.status == 0)
        return fixture
    }

    // MARK: - Nothing is written

    @Test("A dry run leaves the file's bytes exactly as they were", arguments: verbs)
    func dryRunLeavesTheFileAlone(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana"])

        #expect(run.status == 0)
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A dry run appends nothing to the activity log", arguments: verbs)
    func dryRunLeavesTheLogAlone(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana"])

        #expect(run.status == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }

    @Test("undo --dry-run leaves the file and the log exactly as they were")
    func undoLeavesTheFileAndTheLogAlone() throws {
        let fixture = try Self.seeded()
        let before = try Data(contentsOf: fixture.file)
        let log = try Data(contentsOf: fixture.activityLog)

        let run = try fixture.run("undo", fixture.file.path, "--dry-run", "--as", "ana")

        #expect(run.status == 0)
        try #expect(Data(contentsOf: fixture.file) == before)
        try #expect(Data(contentsOf: fixture.activityLog) == log)
    }

    @Test("new --dry-run creates no file")
    func newCreatesNothing() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run("new", Self.freshName, "--dry-run")

        #expect(run.status == 0)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent(Self.freshName).path
            )
        )
    }

    // MARK: - The answer

    @Test("A dry run answers with the write's own report, marked and without revisions", arguments: verbs)
    func dryRunEchoesTheWrite(verb: Verb) throws {
        let previewed = try CommandFixture(fixture: Self.fixtureName)
        let written = try CommandFixture(fixture: Self.fixtureName)

        let dry = try previewed.run(Self.argv(verb, in: previewed) + ["--dry-run", "--as", "ana"])
        let real = try written.run(Self.argv(verb, in: written) + ["--as", "ana"])

        #expect(dry.status == real.status)
        let expected = ([DryRunOption.marker] + Self.withoutRevisions(real.stdout)).joined(separator: "\n")
        #expect(dry.stdout == expected)
    }

    @Test("undo --dry-run answers with the undo's own rows, marked and without the revision")
    func undoEchoesTheWrite() throws {
        let previewed = try Self.seeded()
        let written = try Self.seeded()

        let dry = try previewed.run("undo", previewed.file.path, "--dry-run", "--as", "ana")
        let real = try written.run("undo", written.file.path, "--as", "ana")

        #expect(dry.status == real.status)
        let expected = ([DryRunOption.marker] + Self.withoutRevisions(real.stdout)).joined(separator: "\n")
        #expect(Self.maskingTimes(dry.stdout) == Self.maskingTimes(expected))
    }

    @Test("The marker is the first thing on standard output", arguments: verbs)
    func theMarkerLeads(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana"])

        #expect(run.stdout.hasPrefix(DryRunOption.marker + "\n"))
    }

    @Test("The marker leads undo's output too")
    func theMarkerLeadsUndo() throws {
        let fixture = try Self.seeded()

        let run = try fixture.run("undo", fixture.file.path, "--dry-run", "--as", "ana")

        #expect(run.stdout.hasPrefix(DryRunOption.marker + "\n"))
    }

    @Test("A real write is unmarked and still carries its revision", arguments: verbs)
    func aRealWriteIsUnchanged(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--as", "ana"])

        #expect(run.status == 0)
        #expect(!run.stdout.contains(DryRunOption.marker))
        #expect(run.stdout.contains("revision ") || run.stdout.contains("document  "))
    }

    @Test("A real undo is unmarked and still carries its revision")
    func aRealUndoIsUnchanged() throws {
        let fixture = try Self.seeded()

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(run.status == 0)
        #expect(!run.stdout.contains(DryRunOption.marker))
        #expect(run.stdout.contains("revision "))
    }

    // MARK: - Lint

    @Test("A dry run prints the findings the write would introduce")
    func dryRunPrintsIntroducedFindings() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(
            "vars", "rm", fixture.file.path, "primaryColor", "--force", "--dry-run"
        )

        #expect(run.status == 0)
        #expect(run.stdout.contains("error unresolved-variable"))
        #expect(run.stdout.contains("$primaryColor"))
    }

    @Test("A dry run that breaks nothing prints no findings")
    func aCleanDryRunPrintsNoFindings() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run("vars", "rm", fixture.file.path, "spacing", "--dry-run")

        #expect(run.status == 0)
        #expect(!run.stdout.contains("unresolved-variable"))
        #expect(run.stdout == DryRunOption.marker + "\nRemoved spacing (number).\n")
    }

    @Test("Findings do not change the exit code")
    func findingsDoNotChangeTheExitCode() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(
            "vars", "rm", fixture.file.path, "primaryColor", "--force", "--dry-run"
        )

        #expect(run.status == 0)
    }

    // MARK: - Refusals

    @Test("A refused dry run keeps the write's exit code and prints no report")
    func aRefusedRemovalStillFails() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("vars", "rm", fixture.file.path, "primaryColor", "--dry-run")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(!run.stdout.contains(DryRunOption.marker))
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("new --dry-run refuses an existing path exactly as the write would")
    func newRefusesAnExistingPath() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run("new", fixture.file.path, "--dry-run")

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("already exists"))
    }

    @Test("new --dry-run refuses a missing parent directory exactly as the write would")
    func newRefusesAMissingParent() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run("new", "nowhere/design.pen", "--dry-run")

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("does not exist"))
    }

    @Test("undo --dry-run with nothing to reverse is the clean negative it always was")
    func undoWithNothingToReverse() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run("undo", fixture.file.path, "--dry-run", "--as", "ana")

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        #expect(run.stdout.isEmpty)
    }

    // MARK: - JSON

    @Test("--json carries dryRun and no revision", arguments: verbs)
    func jsonCarriesTheFlagAndDropsTheRevision(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(
            Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana", "--json"]
        )

        let object = try Self.json(run)
        #expect(object["dryRun"] as? Bool == true)
        #expect(object["revision"] == nil)
        #expect(object["documentRevision"] == nil)
    }

    @Test("undo --json carries dryRun and no revision")
    func undoJSONCarriesTheFlag() throws {
        let fixture = try Self.seeded()

        let run = try fixture.run("undo", fixture.file.path, "--dry-run", "--as", "ana", "--json")

        let object = try Self.json(run)
        #expect(object["dryRun"] as? Bool == true)
        #expect(object["revision"] == nil)
        #expect(object["undone"] != nil)
    }

    @Test("--json carries the findings the write would introduce")
    func jsonCarriesTheFindings() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(
            "vars", "rm", fixture.file.path, "primaryColor", "--force", "--dry-run", "--json"
        )

        let object = try Self.json(run)
        let findings = try #require(object["lint"] as? [[String: Any]])
        #expect(findings.allSatisfy { $0["check"] as? String == "unresolved-variable" })
        #expect(!findings.isEmpty)
    }

    @Test("A real write's --json is unchanged: no dryRun key, no lint, and the revision is there", arguments: verbs)
    func aRealWriteJSONIsUnchanged(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--as", "ana", "--json"])

        let object = try Self.json(run)
        #expect(object["dryRun"] == nil)
        #expect(object["lint"] == nil)
        #expect(object["revision"] != nil || object["documentRevision"] != nil)
    }
}
