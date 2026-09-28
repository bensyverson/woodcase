//
//  ApplyParityTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A batch line must do what the verb of the same name does.
///
/// `apply` is the bulk form of the single-node verbs, and an agent that learns `cp`
/// on argv writes `{"op":"cp",…}` expecting the same grammar. Every gap here was a
/// place where the batch refused what the verb accepted, or lacked something every
/// other write had — each one costing an agent a debugging round trip against a tool
/// that had already taught it otherwise.
@MainActor
@Suite("apply / verb parity")
struct ApplyParityTests {
    // MARK: - Helpers

    private func writeOps(_ jsonl: String, into fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent("ops-\(UUID().uuidString).jsonl")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    /// The rev of one node, as `tree --json` reports it.
    private func rev(_ fixture: CommandFixture, _ id: String) throws -> String {
        let run = try fixture.run("tree", fixture.file.path, "--json")
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        let row = try #require(report.rows.first { $0.id == id }, "no row for \(id)")
        return row.rev
    }

    // MARK: - Path-keyed props on the cp op

    @Test("A cp line with a Path/kind.content key overrides inside the instance, as the verb does")
    func batchCopyWritesAnOverrideInsideTheInstance() throws {
        let batched = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            """
            {"op":"cp","source":"Component","parent":"Canvas",\
            "props":{"common.name":"Chip","Label/kind.content":"Hello"}}
            """,
            into: batched
        )

        let run = try batched.run("apply", batched.file.path, "-F", opsPath)

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        let copy = try #require(try PenFileProbe(batched.file).node("Canvas/Chip"))
        #expect(overrides(of: copy)["Lbl01"]?.properties["content"] == .string("Hello"))
    }

    @Test("A cp line with a Path/kind.content key sets inside a deep copy, as the verb does")
    func batchCopyWritesInsideADeepCopy() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            """
            {"op":"cp","source":"Canvas","parent":"Board",\
            "props":{"common.name":"Canvas2","Title/kind.content":"Deep"}}
            """,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Board/Canvas2/Title")?.textContent == "Deep")
        #expect(probe.node("Canvas/Title")?.textContent != "Deep", "the source is untouched")
    }

    @Test("A cp line whose path names nothing fails that line and changes nothing")
    func batchCopyRefusesAnUnknownPath() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let opsPath = try writeOps(
            """
            {"op":"cp","source":"Component","parent":"Canvas",\
            "props":{"common.name":"Chip","Nowhere/kind.content":"Hello"}}
            """,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 1)
        #expect(run.stdout.contains("Nowhere"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - "parent":"document"

    @Test("A batch add with parent \"document\" creates a root node")
    func batchAddAcceptsTheDocumentRoot() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            #"{"op":"add","parent":"document","node":{"type":"frame","name":"Root2"}}"#,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.roots.map(\.common.name).contains("Root2"))
    }

    @Test("A batch cp and mv take parent \"document\" too")
    func batchCopyAndMoveAcceptTheDocumentRoot() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            """
            {"op":"cp","source":"Canvas/Cards/First","parent":"document","props":{"common.name":"Loose"}}
            {"op":"mv","target":"Canvas/Cards/Second","parent":"document"}
            """,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        let names = try PenFileProbe(fixture.file).roots.map(\.common.name)
        #expect(names.contains("Loose"))
        #expect(names.contains("Second"))
    }

    @Test("A root genuinely named `document` is still reachable by its id")
    func aLiteralDocumentNameIsStillAddressableByID() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let renamed = try fixture.run("set", fixture.file.path, "Board", "common.name=document")
        #expect(renamed.status == 0, "set failed: \(renamed.stderr)")
        let opsPath = try writeOps(
            ##"{"op":"add","parent":"#Brd01","node":{"type":"frame","name":"Inner"}}"##,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath)

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        #expect(try PenFileProbe(fixture.file).node("document/Inner") != nil)
    }

    // MARK: - `apply --guard`

    @Test("apply --guard quoting the current document revision applies the batch")
    func applyGuardHoldsOnTheCurrentRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"}}"#,
            into: fixture
        )
        let tree = try fixture.run("tree", fixture.file.path, "--json")
        let pin = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8)).revision

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--guard", pin)

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent == "Hi")
    }

    @Test("apply --guard on a moved premise exits 3, names both revisions and writes nothing")
    func applyGuardRefusesAMovedPremise() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let stale = try rev(fixture, "Ttl01")
        let moved = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Moved", "--as", "other"
        )
        #expect(moved.status == 0, "set failed: \(moved.stderr)")
        let before = try Data(contentsOf: fixture.file)
        let opsPath = try writeOps(
            #"{"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Nope"}}"#,
            into: fixture
        )

        let run = try fixture.run(
            "apply", fixture.file.path, "-F", opsPath, "--guard", "Canvas/Title=\(stale)"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains(stale))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("A bare apply --guard pins the whole document, the only thing a batch acts on")
    func aBareApplyGuardPinsTheDocument() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let tree = try fixture.run("tree", fixture.file.path, "--json")
        let stale = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8)).revision
        let moved = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Moved")
        #expect(moved.status == 0, "set failed: \(moved.stderr)")
        let opsPath = try writeOps(
            #"{"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Nope"}}"#,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--guard", stale)

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(try PenFileProbe(fixture.file).node("Canvas/Cards/First")?.common.name == "First")
    }

    @Test("apply --guard is refused when it is not a revision, before the file is opened")
    func applyGuardRefusesANonRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"}}"#,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--guard", "nonsense")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("not a revision"))
    }

    @Test("An argv guard and a per-line guard are both asserted")
    func argvAndLineGuardsBothApply() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let stale = try rev(fixture, "Cd101")
        let moved = try fixture.run("set", fixture.file.path, "Canvas/Cards/First", "common.name=Gone")
        #expect(moved.status == 0, "set failed: \(moved.stderr)")
        let tree = try fixture.run("tree", fixture.file.path, "--json")
        let fresh = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8)).revision
        let opsPath = try writeOps(
            """
            {"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"},\
            "guard":{"node":"Canvas/Cards/Gone","rev":"\(stale)"}}
            """,
            into: fixture
        )

        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--guard", fresh)

        #expect(run.status == ExitCode.conflict.rawValue, "the line's own guard should still fail")
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent != "Hi")
    }

    // MARK: - `-F /dev/null`

    @Test("apply -F /dev/null is an empty batch, not an error")
    func devNullIsAnEmptyBatch() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("apply", fixture.file.path, "-F", "/dev/null")

        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        #expect(run.stdout.contains("0 applied, 0 failed, 0 cascaded"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("A batch file that does not exist still names the path and exits 4")
    func aMissingBatchFileStillFails() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("apply", fixture.file.path, "-F", "/nope/missing.jsonl")

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("/nope/missing.jsonl"))
    }

    @Test("A directory given to -F is refused as a directory")
    func aDirectoryIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("apply", fixture.file.path, "-F", fixture.root.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("directory"))
    }
}
