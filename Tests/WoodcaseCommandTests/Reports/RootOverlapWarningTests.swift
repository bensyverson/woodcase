//
//  RootOverlapWarningTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A write that leaves one root sitting on another still succeeds, and says so on
/// standard error — never on standard output, which stays the answer.
@Suite("root overlap warnings")
struct RootOverlapWarningTests {
    /// The fixture: Home at 0,0 200×100 with a Panel inside it, Checkout at 200,0.
    private func fixture() throws -> CommandFixture {
        try CommandFixture(fixture: "lint/artboard-overlap-clean.pen")
    }

    // MARK: - set

    @Test("A set that slides one root onto another succeeds and warns on stderr")
    func setWarnsWithoutFailing() throws {
        let fixture = try fixture()
        let run = try fixture.run("set", fixture.file.path, "Chk01", "common.x=100")

        #expect(run.status == 0)
        #expect(run.stdout.contains("Checkout  Chk01"))
        #expect(!run.stdout.contains("artboard-overlap"))

        let warnings = run.stderr.split(separator: "\n").filter { $0.contains("artboard-overlap") }
        #expect(warnings.count == 1)
        let line = try #require(warnings.first).description
        #expect(line.hasPrefix("warning artboard-overlap  Checkout (Chk01)  "))
        #expect(line.contains("100,0 200×100"))
        #expect(line.contains("Home (Home1) 0,0 200×100"))
        #expect(line.contains("woodcase set \(fixture.file.path) Chk01 common.x=300"))
    }

    @Test("--json carries the same warning in a warnings array")
    func setJSONCarriesWarnings() throws {
        let fixture = try fixture()
        let run = try fixture.run("set", fixture.file.path, "Chk01", "common.x=100", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        let warnings = try #require(report.warnings)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("artboard-overlap"))
        #expect(warnings[0].contains("Home (Home1)"))
    }

    @Test("A set that leaves the roots clear says nothing at all")
    func setWithoutOverlapIsSilent() throws {
        let fixture = try fixture()
        let run = try fixture.run("set", fixture.file.path, "Chk01", "common.x=400")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
    }

    @Test("--json omits the warnings key when there is nothing to warn about")
    func cleanJSONHasNoWarningsKey() throws {
        let fixture = try fixture()
        let run = try fixture.run("set", fixture.file.path, "Chk01", "common.x=400", "--json")

        #expect(run.status == 0)
        #expect(!run.stdout.contains("warnings"))
    }

    @Test("An overlap the write did not cause is left to lint, not repeated on every edit")
    func preExistingOverlapDoesNotWarn() throws {
        let fixture = try CommandFixture(fixture: "lint/artboard-overlap-trips.pen")
        let run = try fixture.run("set", fixture.file.path, "Set01", "common.name=Preferences")

        #expect(run.status == 0)
        #expect(!run.stderr.contains("artboard-overlap"))
    }

    // MARK: - add, cp, mv

    @Test("An add that places a root on top of another warns")
    func addWarns() throws {
        let fixture = try fixture()
        let subtree = fixture.root.appendingPathComponent("subtree.json")
        try Data(#"{"type":"frame","name":"Cart","x":50,"y":0,"width":100,"height":100}"#.utf8)
            .write(to: subtree)

        let run = try fixture.run("add", fixture.file.path, "document", "-F", subtree.path)

        #expect(run.status == 0)
        #expect(run.stderr.contains("warning artboard-overlap"))
        #expect(run.stderr.contains("Home (Home1)"))
    }

    @Test("A cp given coordinates that land on another root warns")
    func copyWarns() throws {
        let fixture = try fixture()
        let run = try fixture.run(
            "cp", fixture.file.path, "Home", "document", "common.name=Home Copy", "common.x=50"
        )

        #expect(run.status == 0)
        #expect(run.stderr.contains("warning artboard-overlap"))
        #expect(run.stderr.contains("Home Copy"))
    }

    @Test("A cp with no coordinates is auto-placed, so it never warns")
    func copyWithoutCoordinatesIsSilent() throws {
        let fixture = try fixture()
        let run = try fixture.run("cp", fixture.file.path, "Home", "document", "common.name=Home Copy")

        #expect(run.status == 0)
        #expect(!run.stderr.contains("artboard-overlap"))
    }

    @Test("A mv that promotes a child to a root keeps its offset, and warns when it lands on one")
    func moveWarns() throws {
        let fixture = try fixture()
        let run = try fixture.run("mv", fixture.file.path, "Home/Panel", "document")

        #expect(run.status == 0)
        #expect(run.stderr.contains("warning artboard-overlap"))
        #expect(run.stderr.contains("Panel (Pnl01)"))
    }

    // MARK: - apply

    @Test("A batch line that leaves an overlap warns, and the report carries it")
    func applyWarns() throws {
        let fixture = try fixture()
        let ops = fixture.root.appendingPathComponent("ops.jsonl")
        try Data(#"{"op":"set","target":"Chk01","props":{"common.x":100}}"#.utf8).write(to: ops)

        let run = try fixture.run("apply", fixture.file.path, "-F", ops.path, "--json")

        #expect(run.status == 0)
        #expect(run.stderr.contains("warning artboard-overlap"))
        let report = try JSONDecoder().decode(BatchReport.self, from: Data(run.stdout.utf8))
        let warnings = try #require(report.warnings)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("Checkout (Chk01)"))
    }

    @Test("A batch that ends with the roots clear warns about nothing")
    func applyWithoutOverlapIsSilent() throws {
        let fixture = try fixture()
        let ops = fixture.root.appendingPathComponent("ops.jsonl")
        let lines = [
            #"{"op":"set","target":"Chk01","props":{"common.x":100}}"#,
            #"{"op":"set","target":"Chk01","props":{"common.x":500}}"#,
        ].joined(separator: "\n")
        try Data(lines.utf8).write(to: ops)

        let run = try fixture.run("apply", fixture.file.path, "-F", ops.path)

        #expect(run.status == 0)
        #expect(!run.stderr.contains("artboard-overlap"))
    }

    // MARK: - lint agrees

    @Test("lint reports the overlap a write warned about, under the same check id")
    func lintAgreesWithTheWarning() throws {
        let fixture = try fixture()
        let write = try fixture.run("set", fixture.file.path, "Chk01", "common.x=100")
        #expect(write.status == 0)

        let lint = try fixture.run("lint", fixture.file.path)
        #expect(lint.status == 1)
        #expect(lint.stdout.contains("warning artboard-overlap  Checkout (Chk01)"))
    }
}
