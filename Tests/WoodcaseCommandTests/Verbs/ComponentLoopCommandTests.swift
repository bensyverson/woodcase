//
//  ComponentLoopCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Component loops at the command line: a write that would close one fails, naming it,
/// and leaves the file alone; a file that holds one reads with a loud error, and `lint`
/// reports it.
@Suite("Component loops")
struct ComponentLoopCommandTests {
    /// Writes `text` beside the fixture and returns its URL.
    private static func write(_ text: String, to name: String, in fixture: CommandFixture) throws -> URL {
        let url = fixture.root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("`add` of an instance that closes a loop exits non-zero, names the loop and leaves the file")
    func addClosingLoopFails() throws {
        let fixture = try CommandFixture(fixture: "loops/open.pen")
        let before = try Data(contentsOf: fixture.file)
        let body = try Self.write(#"{"type":"ref","name":"Back","ref":"CmpA1"}"#, to: "back.json", in: fixture)

        let run = try fixture.run("add", fixture.file.path, "Badge", "-F", body.path, "--as", "ana")

        #expect(run.status != 0)
        #expect(run.stderr.contains("contain each other"))
        #expect(run.stderr.contains("Badge (CmpB1) → Card (CmpA1) → Badge (CmpB1)"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("A batch line that closes a loop fails, and the batch exits non-zero")
    func batchClosingLoopFails() throws {
        let fixture = try CommandFixture(fixture: "loops/open.pen")
        let batch = try Self.write("""
        {"op":"set","target":"Card/TxtA1","props":{"kind.content":"changed"}}
        {"op":"add","parent":"Badge","node":{"type":"ref","name":"Back","ref":"CmpA1"}}
        """, to: "ops.jsonl", in: fixture)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path, "--as", "ana")

        // A batch applies the lines that apply and reports each one that fails.
        #expect(run.status != 0)
        #expect(run.stdout.contains("line 1  failed   this would make components contain each other"))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8).contains("\"Back\"") == false)
    }

    @Test("`lint` reports each loop as an error")
    func lintReportsLoop() throws {
        let fixture = try CommandFixture(fixture: "loops/looped.pen")
        let run = try fixture.run("lint", fixture.file.path, "--json")

        #expect(run.status == 1)
        let findings = try JSONDecoder().decode([LintFinding].self, from: Data(run.stdout.utf8))
        let loops = findings.filter { $0.check == .componentLoop }
        #expect(loops.count == 1)
        #expect(loops.first?.severity == .error)
        #expect(loops.first?.message.contains("Card → Badge → Card") == true)
    }

    @Test(
        "Every verb that reads a file with a loop says so on standard error",
        arguments: ["tree", "lint", "get"]
    )
    func readsSayLoop(verb: String) throws {
        let fixture = try CommandFixture(fixture: "loops/looped.pen")
        let run = verb == "get" ? try fixture.run(verb, fixture.file.path, "Card") : try fixture.run(verb, fixture.file.path)

        #expect(run.stderr.contains("woodcase: error:"))
        #expect(run.stderr.contains("holds components that contain each other: Card → Badge → Card"))
        let lines = run.stderr.split(separator: "\n").filter { $0.contains("contain each other") }
        #expect(lines.count == 1, "said once per command: \(lines)")
    }
}
