//
//  CopyEachTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase cp --each rows.jsonl` — one copy per row, each row carrying its own
/// content.
///
/// `--times` repeats a copy but cannot vary what is *in* it, so every agent that
/// needed a list of cards wrote a generator: read a table, emit N `cp` invocations or
/// a batch of them, reconcile the ids. `--each` is that loop, in the verb: the rows are
/// the data, the keys are the same keys `cp` takes on argv, and `{n}` still counts.
@Suite("woodcase cp --each")
struct CopyEachTests {
    // MARK: - Helpers

    private func writeRows(_ jsonl: String, into fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent("rows-\(UUID().uuidString).jsonl")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    // MARK: - The loop

    @Test("Three rows make three copies whose named descendants carry each row's values")
    func threeRowsMakeThreeDressedCopies() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(
            """
            {"common.name":"Chip A","Label/kind.content":"Alpha"}
            {"common.name":"Chip B","Label/kind.content":"Beta"}
            {"common.name":"Chip C","Label/kind.content":"Gamma"}
            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas/Cards", "--each", rows
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 4, "expected three created roots and a document line: \(run.stdout)")
        #expect(lines[0].hasPrefix("Chip A  "))
        #expect(lines[1].hasPrefix("Chip B  "))
        #expect(lines[2].hasPrefix("Chip C  "))
        #expect(lines[3].hasPrefix("document  "))

        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Canvas/Cards/Chip A"))["Lbl01"]?
            .properties["content"] == .string("Alpha"))
        #expect(overrides(of: probe.node("Canvas/Cards/Chip B"))["Lbl01"]?
            .properties["content"] == .string("Beta"))
        #expect(overrides(of: probe.node("Canvas/Cards/Chip C"))["Lbl01"]?
            .properties["content"] == .string("Gamma"))
    }

    @Test("A deep copy's descendants take the row's values too")
    func rowsDressADeepCopy() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(
            """
            {"common.name":"One","Title/kind.content":"First page"}
            {"common.name":"Two","Title/kind.content":"Second page"}
            """,
            into: fixture
        )

        let run = try fixture.run("cp", fixture.file.path, "Canvas", "document", "--each", rows)

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("One/Title")?.textContent == "First page")
        #expect(probe.node("Two/Title")?.textContent == "Second page")
        #expect(probe.node("Canvas/Title")?.textContent != "First page", "the source is untouched")
    }

    @Test("{n} is the 1-based row number, in root and descendant values alike")
    func placeholderCountsRows() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(
            """
            {"common.name":"Row {n}","Label/kind.content":"Item {n} of two"}
            {"common.name":"Row {n}","Label/kind.content":"Item {n} of two"}
            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas/Cards", "--each", rows
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Canvas/Cards/Row 1"))["Lbl01"]?
            .properties["content"] == .string("Item 1 of two"))
        #expect(overrides(of: probe.node("Canvas/Cards/Row 2"))["Lbl01"]?
            .properties["content"] == .string("Item 2 of two"))
    }

    @Test("An argv assignment is the default for every row, and a row key wins over it")
    func argvAssignmentsAreRowDefaults() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(
            """
            {"common.name":"Kept"}
            {"common.name":"Own","Label/kind.content":"Mine"}
            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas/Cards",
            "Label/kind.content=Shared", "--each", rows
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Canvas/Cards/Kept"))["Lbl01"]?
            .properties["content"] == .string("Shared"))
        #expect(overrides(of: probe.node("Canvas/Cards/Own"))["Lbl01"]?
            .properties["content"] == .string("Mine"))
    }

    @Test("--at places the copies in row order from the given index")
    func placesRowsInOrderAtAnIndex() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(
            """
            {"common.name":"A"}
            {"common.name":"B"}
            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "--each", rows, "--at", "0"
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let cards = try #require(try PenFileProbe(fixture.file).node("Canvas/Cards"))
        #expect(PenFileProbe.children(of: cards).map(\.common.name) == ["A", "B", "First", "Second"])
    }

    @Test("Blank lines in the rows file are skipped, as they are in a batch")
    func blankRowLinesAreSkipped() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(
            """
            {"common.name":"A"}

            {"common.name":"B"}

            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards", "--each", rows
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        #expect(run.stdoutLines.count == 3)
    }

    // MARK: - All or nothing

    @Test("A row key that names no descendant fails the whole cp before any write")
    func aBadRowKeyRefusesEverything() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let rows = try writeRows(
            """
            {"common.name":"Good 1","Label/kind.content":"Fine"}
            {"common.name":"Good 2","Label/kind.content":"Fine"}
            {"common.name":"Bad","Nowhere/kind.content":"Boom"}
            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas/Cards", "--each", rows
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("row 3"), "the message must name the row: \(run.stderr)")
        #expect(run.stderr.contains("Nowhere"), "the message must name the key: \(run.stderr)")
        #expect(run.stderr.contains("woodcase tree"), "the message must name the next command")
        #expect(try Data(contentsOf: fixture.file) == before, "nothing was written")
    }

    @Test("A row that is not a JSON object names the row and changes nothing")
    func aMalformedRowIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let rows = try writeRows(
            """
            {"common.name":"Good"}
            not json
            """,
            into: fixture
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards", "--each", rows
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("row 2"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("An empty rows file copies nothing, and says so rather than failing")
    func anEmptyRowsFileCopiesNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let rows = try writeRows("", into: fixture)

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards", "--each", rows
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("no rows"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - `--each` and `--times`

    @Test("--each and --times together are refused, saying which one to keep")
    func eachAndTimesAreMutuallyExclusive() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let rows = try writeRows(#"{"common.name":"A"}"#, into: fixture)

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "--each", rows, "--times", "2"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--each"))
        #expect(run.stderr.contains("--times"))
    }

    // MARK: - The help

    @Test("cp --help teaches --each, and says it is not for use with --times")
    func helpTeachesEach() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", "--help")

        #expect(run.stdout.contains("--each"))
        #expect(run.stdout.contains("rows.jsonl"))
        #expect(run.stdout.contains("--times"))
    }
}
