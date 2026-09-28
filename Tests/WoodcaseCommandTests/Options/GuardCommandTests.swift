//
//  GuardCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `--guard` is the premise assertion: "nothing *anyone else* has done since my read
/// moved what I reasoned about."
///
/// It differs from `--rev` in two ways this suite pins. It is evaluated once, at
/// transaction entry, so a batch's own earlier lines never trip a later line's guard —
/// which is the property that made `--rev` unusable for a 36-line batch. And it may be
/// scoped to any ancestor the caller read, not only to the node the write touches.
@Suite("woodcase --guard")
struct GuardCommandTests {
    // MARK: - Helpers

    /// The rev of one node, as `tree --json` reports it.
    private func rev(_ fixture: CommandFixture, _ id: String) throws -> String {
        let run = try fixture.run("tree", fixture.file.path, "--json")
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        let row = try #require(report.rows.first { $0.id == id }, "no row for \(id)")
        return row.rev
    }

    /// The file's bytes, for the assertions that say a refusal wrote nothing.
    private func bytes(_ fixture: CommandFixture) throws -> Data {
        try Data(contentsOf: fixture.file)
    }

    // MARK: - A guard that holds

    @Test("A guard quoting the current revision applies exactly as an unguarded write does")
    func aFreshGuardApplies() throws {
        let guarded = try CommandFixture(fixture: "batch.pen")
        let unguarded = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(guarded, "Ttl01")

        let one = try guarded.run(
            "set", guarded.file.path, "Canvas/Title", "kind.content=Hello", "--guard", pin
        )
        let two = try unguarded.run(
            "set", unguarded.file.path, "Canvas/Title", "kind.content=Hello"
        )

        #expect(one.status == 0)
        #expect(one.stderr.isEmpty)
        // 2Zo: a guard changes nothing about what a write does or answers.
        #expect(one.stdout == two.stdout)
        #expect(try bytes(guarded) == bytes(unguarded))
    }

    @Test("An ancestor guard pins the whole subtree the caller read")
    func anAncestorGuardApplies() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(fixture, "Cnv01")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello",
            "--guard", "Canvas=\(pin)"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
    }

    // MARK: - A guard that has moved

    @Test("A stale guard refuses the write, naming both revisions and the next command")
    func aStaleGuardRefuses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(fixture, "Ttl01")
        let foreign = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Moved", "--as", "ana"
        )
        #expect(foreign.status == 0)
        let before = try bytes(fixture)

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--guard", pin
        )

        let current = try rev(fixture, "Ttl01")
        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Canvas/Title"))
        #expect(run.stderr.contains(pin))
        #expect(run.stderr.contains(current))
        #expect(run.stderr.contains("ana"))
        #expect(run.stderr.contains("woodcase get"))
        #expect(try bytes(fixture) == before)
    }

    @Test("A definition edit trips a guard pinned on a frame full of instances")
    func aDefinitionEditTripsAFrameGuard() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        // Board holds Chip, an instance of Component. Nothing the file stores *under*
        // Board changes here — only what Board draws.
        let pin = try rev(fixture, "Brd01")
        let foreign = try fixture.run(
            "set", fixture.file.path, "Component/Label", "kind.content=chipped", "--as", "ana"
        )
        #expect(foreign.status == 0)

        let run = try fixture.run(
            "set", fixture.file.path, "Board/Chip", "common.name=Chippy",
            "--guard", "Board=\(pin)"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("Board"))
        #expect(run.stderr.contains(pin))
    }

    @Test("An unattributed foreign write is named as one, not left out")
    func anUnattributedWriterIsNamed() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(fixture, "Ttl01")
        let foreign = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Moved")
        #expect(foreign.status == 0)

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--guard", pin
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("unattributed"))
    }

    // MARK: - Batches

    @Test("A later line's guard passes when only earlier lines of the same batch moved the subtree")
    func aBatchDoesNotTripItsOwnGuards() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(fixture, "Cnv01")
        let batch = fixture.root.appendingPathComponent("ops.jsonl")
        try """
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"One"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.width":140}}
        {"op":"set","target":"Canvas/Cards/Second","props":{"kind.width":160},"guard":{"node":"Canvas","rev":"\(pin)"}}
        """.write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path, "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(run.stdout.contains("3 applied"))
    }

    @Test("The same batch line guarded with --rev fails, which is the difference guards exist for")
    func theSameLineGuardedWithRevFails() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(fixture, "Cnv01")
        let batch = fixture.root.appendingPathComponent("ops.jsonl")
        try """
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"One"}}
        {"op":"set","target":"Canvas","props":{"kind.height":320},"rev":"\(pin)"}
        """.write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path, "--as", "ana")

        #expect(run.status == ExitCode.conflict.rawValue)
    }

    @Test("A stale guard on any line refuses the whole batch before a single line applies")
    func aStaleGuardRefusesTheWholeBatch() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let stale = try rev(fixture, "Cnv01")
        let foreign = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Moved", "--as", "ana"
        )
        #expect(foreign.status == 0)
        let before = try bytes(fixture)

        let batch = fixture.root.appendingPathComponent("ops.jsonl")
        try """
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.width":140}}
        {"op":"set","target":"Canvas/Cards/Second","props":{"kind.width":160},"guard":{"node":"Canvas","rev":"\(stale)"}}
        """.write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path, "--as", "bo")

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Canvas"))
        // Line 0 was perfectly good and still did not run: a guard is an entry gate.
        #expect(try bytes(fixture) == before)
    }

    @Test("A bare guard on a batch line pins that line's own target")
    func aBareGuardInABatchPinsTheTarget() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let stale = try rev(fixture, "Ttl01")
        let foreign = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Moved", "--as", "ana"
        )
        #expect(foreign.status == 0)

        let batch = fixture.root.appendingPathComponent("ops.jsonl")
        try #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"},"guard":"\#(stale)"}"#
            .write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path)

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("Canvas/Title"))
    }

    // MARK: - Refusals that teach

    @Test("A --guard that is not a revision says what one looks like and where to get it")
    func aMalformedGuardTeaches() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--guard", "Canvas"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--guard"))
        #expect(run.stderr.contains("woodcase get"))
    }

    @Test("A guard on a node the document no longer holds is a conflict, not a silent pass")
    func aGuardOnAMissingNodeRefuses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let pin = try rev(fixture, "Cd201")
        let foreign = try fixture.run("rm", fixture.file.path, "Canvas/Cards/Second", "--as", "ana")
        #expect(foreign.status == 0)

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello",
            "--guard", "Canvas/Cards/Second=\(pin)"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("Canvas/Cards/Second"))
    }

    @Test("A guard naming a batch tag is refused: nothing a line creates exists at entry")
    func aGuardOnATagIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let batch = fixture.root.appendingPathComponent("ops.jsonl")
        try """
        {"op":"add","parent":"Canvas","tag":"hero","node":{"type":"frame","name":"Hero"}}
        {"op":"set","target":"@hero","props":{"kind.width":10},"guard":{"node":"@hero","rev":"0000000000000000"}}
        """.write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("@hero"))
    }

    // MARK: - Every write verb takes one

    @Test("Every single write verb accepts --guard, and a stale one refuses it")
    func everyWriteVerbTakesAGuard() throws {
        let stale = "0000000000000000"
        let invocations: [[String]] = [
            ["set", "Canvas/Title", "kind.content=Hi"],
            ["add", "Canvas", "-F", "-"],
            ["cp", "Canvas/Title", "Canvas"],
            ["mv", "Canvas/Title", "Board"],
            ["rm", "Canvas/Title"],
            ["override", "Board/Chip/Label", "content=Hi"],
            ["replace", "Canvas/Title", "-F", "-"],
        ]

        for invocation in invocations {
            let fixture = try CommandFixture(fixture: "batch.pen")
            var arguments = [invocation[0], fixture.file.path] + invocation.dropFirst()
            arguments += ["--guard", stale]
            let subtree = Data(#"{"type":"text","name":"Title","content":"x"}"#.utf8)
            let run = try fixture.run(arguments, stdin: subtree)

            #expect(
                run.status == ExitCode.conflict.rawValue,
                "\(invocation[0]) exited \(run.status): \(run.stderr)"
            )
        }
    }
}
