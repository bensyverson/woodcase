//
//  DryRunTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `--dry-run` is the write, rehearsed: the same lock, the same guards, the same
/// settling, the same answer — and then nothing on disk.
///
/// Two properties make it worth having, and this suite pins both. What it prints is
/// what the real write prints, so a caller can rehearse and then commit without
/// re-reading the output; and it says what the result would fail `lint` on, which is the
/// thing a caller could not get any other way without writing first.
@Suite("woodcase --dry-run")
struct DryRunTests {
    // MARK: - The verbs under test

    /// One write verb, as the argv that follows the program name.
    ///
    /// `@file`, `@subtree` and `@ops` stand for paths only the fixture knows.
    struct Verb: CustomStringConvertible {
        /// The verb's name, which is also this case's label in the test output.
        let name: String

        /// The command line, with placeholders for the fixture's paths.
        let argv: [String]

        /// Whether two runs of this verb name the same ids.
        ///
        /// `add` and `cp` mint an id per node, so their two runs differ in exactly
        /// those five characters and are compared with the ids masked.
        let idsAreStable: Bool

        var description: String {
            name
        }
    }

    /// Every verb that writes through ``Woodcase/PenFileTransaction`` and
    /// ``Woodcase/BatchApplier``.
    static let verbs: [Verb] = [
        Verb(name: "add", argv: ["add", "@file", "Board", "-F", "@subtree"], idsAreStable: false),
        Verb(name: "apply", argv: ["apply", "@file", "-F", "@ops"], idsAreStable: true),
        Verb(name: "cp", argv: ["cp", "@file", "Canvas/Cards/First", "Board"], idsAreStable: false),
        Verb(name: "mv", argv: ["mv", "@file", "Canvas/Title", "Board"], idsAreStable: true),
        Verb(
            name: "override",
            argv: ["override", "@file", "Board/Chip/Label", "content=Hi"],
            idsAreStable: true
        ),
        Verb(
            name: "replace",
            argv: ["replace", "@file", "Canvas/Title", "-F", "@subtree"],
            idsAreStable: true
        ),
        Verb(name: "rm", argv: ["rm", "@file", "Canvas/Cards/Second"], idsAreStable: true),
        Verb(
            name: "set",
            argv: ["set", "@file", "Canvas/Title", "kind.content=Hello"],
            idsAreStable: true
        ),
    ]

    // MARK: - Helpers

    /// A one-node subtree for `add` and `replace`, and a two-line batch for `apply`.
    ///
    /// Both are deliberately clean: they trip no lint check, so a test comparing a dry
    /// run's answer with the real write's is comparing the report and nothing else.
    private static func prepare(_ fixture: CommandFixture) throws {
        let subtree = ##"{"type":"text","name":"Note","content":"Hi","width":40,"height":24,"fill":"#111111"}"##
        try subtree.write(to: fixture.root.appendingPathComponent("sub.json"), atomically: true, encoding: .utf8)
        let ops = """
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"A"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Primo"}}

        """
        try ops.write(to: fixture.root.appendingPathComponent("ops.jsonl"), atomically: true, encoding: .utf8)
    }

    /// A verb's argv with the fixture's own paths substituted in.
    private static func argv(_ verb: Verb, in fixture: CommandFixture) -> [String] {
        verb.argv.map { argument in
            switch argument {
            case "@file": fixture.file.path
            case "@subtree": fixture.root.appendingPathComponent("sub.json").path
            case "@ops": fixture.root.appendingPathComponent("ops.jsonl").path
            default: argument
            }
        }
    }

    /// A real write's answer with every revision taken out of it: the `rev` and
    /// `document` rows a single verb prints, and the ` — revision <hash>` clause on a
    /// batch's summary.
    private static func withoutRevisions(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("rev  ") && !$0.hasPrefix("document  ") }
            .map { line in
                guard let clause = line.range(of: " — revision ") else { return String(line) }
                return String(line[line.startIndex ..< clause.lowerBound])
            }
    }

    /// The output with minted ids blanked, for the verbs that mint one per run.
    private static func normalized(_ output: String, idsAreStable: Bool) -> String {
        guard !idsAreStable else { return output }
        return output.replacing(/[A-Za-z0-9]{5}/) { _ in "#####" }
    }

    // MARK: - Nothing is written

    @Test("A dry run leaves the file's bytes exactly as they were", arguments: verbs)
    func dryRunLeavesTheFileAlone(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try Self.prepare(fixture)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana"])

        #expect(run.status == 0)
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A dry run appends nothing to the activity log", arguments: verbs)
    func dryRunLeavesTheLogAlone(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try Self.prepare(fixture)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana"])

        #expect(run.status == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }

    @Test("A dry run inside a repository does not touch .gitignore")
    func dryRunDoesNotTouchGitignore() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let ignore = fixture.root.appendingPathComponent(".gitignore")

        let run = try fixture.run(
            ["set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--dry-run", "--as", "ana"],
            environment: [ActivityLog.homeEnvironmentVariable: ""]
        )

        #expect(run.status == 0)
        #expect(!FileManager.default.fileExists(atPath: ignore.path))
        #expect(!run.stderr.contains(ActivityLog.ignorePattern))
    }

    @Test("The document's revision is the one it had before the dry run")
    func dryRunLeavesTheRevisionAlone() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try fixture.run("tree", fixture.file.path).stdout

        _ = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--dry-run")

        #expect(try fixture.run("tree", fixture.file.path).stdout == before)
    }

    // MARK: - The answer

    @Test("A dry run answers with the write's own report, marked and without revisions", arguments: verbs)
    func dryRunEchoesTheWrite(verb: Verb) throws {
        let previewed = try CommandFixture(fixture: "batch.pen")
        let written = try CommandFixture(fixture: "batch.pen")
        try Self.prepare(previewed)
        try Self.prepare(written)

        let dry = try previewed.run(Self.argv(verb, in: previewed) + ["--dry-run", "--as", "ana"])
        let real = try written.run(Self.argv(verb, in: written) + ["--as", "ana"])

        #expect(dry.status == real.status)
        let expected = ([DryRunOption.marker] + Self.withoutRevisions(real.stdout)).joined(separator: "\n")
        #expect(
            Self.normalized(dry.stdout, idsAreStable: verb.idsAreStable)
                == Self.normalized(expected, idsAreStable: verb.idsAreStable)
        )
    }

    @Test("The marker is the first thing on standard output", arguments: verbs)
    func theMarkerLeads(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try Self.prepare(fixture)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--dry-run", "--as", "ana"])

        #expect(run.stdout.hasPrefix(DryRunOption.marker + "\n"))
    }

    @Test("A real write is unmarked and still carries its revisions", arguments: verbs)
    func aRealWriteIsUnchanged(verb: Verb) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try Self.prepare(fixture)

        let run = try fixture.run(Self.argv(verb, in: fixture) + ["--as", "ana"])

        #expect(!run.stdout.contains(DryRunOption.marker))
        #expect(run.stdout.contains("revision ") || run.stdout.contains("document  "))
    }

    // MARK: - Lint

    @Test("A dry run prints the findings the write would introduce")
    func dryRunPrintsIntroducedFindings() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Cards/First", "kind.width=900", "--dry-run")

        #expect(run.status == 0)
        #expect(run.stdout.contains("warning clipped  Canvas/Cards/First (Cd101)"))
        #expect(run.stdout.contains("warning clipped  Canvas/Cards/Second (Cd201)"))
    }

    @Test("A dry run does not repeat findings the file already had")
    func dryRunSkipsPreexistingFindings() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Cards/First", "kind.width=900", "--dry-run")

        // The fixture trips `text-without-fill` twice and `clipped` once on its own.
        #expect(!run.stdout.contains("text-without-fill"))
        #expect(!run.stdout.contains("warning clipped  Canvas/Cards (Crd01)"))
    }

    @Test("Findings do not change the exit code: a dry run that would lint dirty still exits 0")
    func findingsDoNotChangeTheExitCode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Cards/First", "kind.width=900", "--dry-run")

        #expect(run.status == 0)
    }

    @Test("apply --dry-run settles every line before it lints")
    func batchLintsTheSettledResult() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let ops = """
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.width":900}}
        {"op":"set","target":"Canvas/Cards","props":{"kind.width":1000}}

        """
        let path = fixture.root.appendingPathComponent("wide.jsonl")
        try ops.write(to: path, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", path.path, "--dry-run")

        #expect(run.status == 0)
        #expect(run.stdout.contains("2 applied, 0 failed, 0 cascaded"))
        // Line 0 alone would clip `First`; line 1 widens its parent past it. Linting
        // after each line would report a finding the finished batch does not have.
        #expect(!run.stdout.contains("(Cd101)"))
    }

    // MARK: - Refusals

    @Test("A dry run refused by a guard exits 3, prints no report, and writes nothing")
    func aRefusedGuardStillConflicts() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let stale = String(repeating: "0", count: 16)

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hi",
            "--guard", stale, "--dry-run"
        )

        #expect(run.status == 3)
        #expect(!run.stdout.contains(DryRunOption.marker))
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A dry run of a batch with a bad line exits the way the real batch would")
    func aFailedLineKeepsItsExitCode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let ops = """
        {"op":"set","target":"Nowhere","props":{"kind.content":"A"}}

        """
        let path = fixture.root.appendingPathComponent("bad.jsonl")
        try ops.write(to: path, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", path.path, "--dry-run")

        #expect(run.status == 1)
        #expect(run.stdout.contains("failed"))
    }

    // MARK: - JSON

    @Test("--json carries dryRun, the findings, and no revision")
    func jsonCarriesTheFlagAndTheFindings() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Cards/First", "kind.width=900", "--dry-run", "--json"
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        #expect(object["dryRun"] as? Bool == true)
        #expect(object["documentRevision"] == nil)
        #expect(object["nodeRevision"] == nil)
        let findings = try #require(object["lint"] as? [[String: Any]])
        #expect(findings.count == 2)
        #expect(findings.allSatisfy { $0["check"] as? String == "clipped" })
    }

    @Test("A real write's --json is unchanged: no dryRun key, and the revisions are there")
    func aRealWriteJSONIsUnchanged() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Cards/First", "kind.width=900", "--json"
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        #expect(object["dryRun"] == nil)
        #expect(object["lint"] == nil)
        #expect(object["documentRevision"] != nil)
    }

    @Test("apply --dry-run --json carries the flag and drops the revision")
    func batchJSONCarriesTheFlag() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try Self.prepare(fixture)

        let run = try fixture.run(
            "apply", fixture.file.path, "-F",
            fixture.root.appendingPathComponent("ops.jsonl").path, "--dry-run", "--json"
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        #expect(object["dryRun"] as? Bool == true)
        #expect(object["documentRevision"] == nil)
    }
}
