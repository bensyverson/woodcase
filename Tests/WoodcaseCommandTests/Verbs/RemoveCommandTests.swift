//
//  RemoveCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase rm` is the verb whose consequence can exceed its target, so its refusal
/// matters as much as its success.
@Suite("woodcase rm")
struct RemoveCommandTests {
    @Test("A node and its descendants go, and the answer names what went")
    func removesANode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("rm", fixture.file.path, "Canvas/Cards/First", "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 2)
        #expect(lines[0] == "Canvas/Cards/First  Cd101")
        #expect(lines[1].hasPrefix("document  "))

        #expect(try PenFileProbe(fixture.file).node("Canvas/Cards/First") == nil)

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.op == .rm)
    }

    @Test("Deleting a component with live instances is refused, naming them and --detach")
    func refusesAComponentWithInstances() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("rm", fixture.file.path, "Component")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Board/Chip"))
        #expect(run.stderr.contains("--detach"))
        #expect(!run.stderr.contains("\"detach\""))
        #expect(try PenFileProbe(fixture.file).root(named: "Component") != nil)
    }

    @Test("--detach is the consequence being opted into: the instances become plain nodes")
    func detachesFirst() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("rm", fixture.file.path, "Component", "--detach")

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.root(named: "Component") == nil)
        let board = try #require(probe.node("Board"))
        let survivors = PenFileProbe.children(of: board)
        #expect(survivors.count == 1)
        #expect(survivors.first?.kind.typeName != "ref")
    }

    @Test("A node that resolves to nothing is a usage error naming the address")
    func unknownNodeIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("rm", fixture.file.path, "Nowhere")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nowhere"))
    }

    @Test("A stale --rev is a conflict, exit 3, and nothing is removed")
    func staleRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "rm", fixture.file.path, "Canvas/Cards/First", "--rev", "0000000000000000"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("Canvas/Cards/First"))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Cards/First") != nil)
    }

    @Test("--json names what was removed and carries no node revision")
    func jsonOutput() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("rm", fixture.file.path, "Canvas/Cards/First", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        #expect(report.path == "Canvas/Cards/First")
        #expect(report.id == "Cd101")
        #expect(report.nodeRevision == nil)
    }
}
