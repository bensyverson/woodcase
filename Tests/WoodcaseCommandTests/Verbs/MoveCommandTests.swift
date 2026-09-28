//
//  MoveCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase mv` relocates a node without changing it, so the interesting parts are
/// where it lands and what it refuses.
@Suite("woodcase mv")
struct MoveCommandTests {
    @Test("A node moves to a new parent at the position asked for")
    func movesANode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("mv", fixture.file.path, "Canvas/Title", "Board", "--at", "0", "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 3)
        #expect(lines[0] == "Board/Title  Ttl01")
        #expect(lines[1].hasPrefix("rev  "))
        #expect(lines[2].hasPrefix("document  "))

        let probe = try PenFileProbe(fixture.file)
        let board = try #require(probe.node("Board"))
        #expect(PenFileProbe.children(of: board).map(\.common.name) == ["Title", "Chip"])
        #expect(probe.node("Canvas/Title") == nil)

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.op == .mv)
    }

    @Test("document as the destination makes the node a root")
    func movesToTheRoot() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("mv", fixture.file.path, "Canvas/Cards", "document")

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.root(named: "Cards") != nil)
        #expect(probe.node("Canvas/Cards") == nil)
    }

    @Test("Moving into a component instance is refused, and says what to do instead")
    func intoAnInstanceIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "mv", fixture.file.path, "Dashboard/Header/Title", "Dashboard/Body/Nav/Label"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("component instance"))
        #expect(run.stderr.contains("detach"))
    }

    @Test("A stale --rev is a conflict, exit 3, naming the node")
    func staleRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "mv", fixture.file.path, "Canvas/Title", "Board", "--rev", "0000000000000000"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("Canvas/Title"))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title") != nil)
    }

    @Test("An --at past the end of the parent says what the range is")
    func indexOutOfRange() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("mv", fixture.file.path, "Canvas/Title", "Board", "--at", "9")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("out of range"))
    }
}
