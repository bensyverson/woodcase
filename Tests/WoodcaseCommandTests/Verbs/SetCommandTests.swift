//
//  SetCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase set` is the verb agents reach for most, so its typed values, its
/// revision guard and its refusals are all pinned here.
@Suite("woodcase set")
struct SetCommandTests {
    @Test("A property is written, and the answer names the node and both revisions")
    func setsAProperty() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 3)
        #expect(lines[0] == "Canvas/Title  Ttl01")
        #expect(lines[1].hasPrefix("rev  "))
        #expect(lines[2].hasPrefix("document  "))

        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent == "Hello")

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.op == .set)
    }

    @Test("A set with no identity is logged as an unattributed write, not dropped")
    func unattributedSetIsLoggedWithAnEmptyIdentity() throws {
        // `CommandFixture` clears $WOODCASE_AS, so no flag and no variable is the
        // whole of the unattributed case. The write must still reach the log: a
        // viewer, `--follow` and the unread dots all read the log and nothing else.
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Hello")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent == "Hello")

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.identity == "")
        #expect(page.events.first?.op == .set)
        #expect(page.events.first?.paths == ["Canvas/Title"])
    }

    @Test("A blank --as is the unattributed writer, not a writer named with spaces")
    func blankIdentityIsUnattributed() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "  ")

        #expect(run.status == 0)
        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.identity == "")
    }

    @Test("A number is written as a number, and several keys land together")
    func typedValues() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Cards/First", "kind.width=240", "common.name=Wide"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Canvas/Cards/Wide")?.frameWidth == .fixed(240))
    }

    @Test("A number written to kind.content is stored as its string, not refused")
    func numberAsContent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=3")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent == "3")
    }

    @Test("A sizing keyword is written as a sizing keyword")
    func sizingKeyword() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Cards/First", "kind.width=fill_container"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Canvas/Cards/First")?.frameWidth == .fillContainer(fallback: nil))
    }

    @Test("A stale --rev is a conflict, exit 3, and the message names the node")
    func staleRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello",
            "--rev", "0000000000000000"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Canvas/Title"))
        #expect(run.stderr.contains("0000000000000000"))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent == "Canvas")
    }

    @Test("The rev a write hands back is the rev the next write can pass")
    func freshRevision() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let first = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=One")
        let revision = try String(#require(first.stdoutLines.first { $0.hasPrefix("rev  ") }).dropFirst(5))

        let second = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Two", "--rev", revision
        )

        #expect(second.status == 0)
        #expect(try PenFileProbe(fixture.file).node("Canvas/Title")?.textContent == "Two")
    }

    @Test("An assignment with no = says how to write one")
    func missingEqualsIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("key=value"))
    }

    @Test("A property the node does not have is refused, listing the ones it does")
    func unknownPropertyIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.nonsense=1")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("kind.nonsense"))
        #expect(run.stderr.contains("kind.content"))
    }

    @Test("set with nothing to set is refused rather than silently doing nothing")
    func noAssignmentsIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("key=value"))
    }

    @Test("A node inside a component instance is sent to override, in CLI words")
    func insideAnInstanceIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Dashboard/Body/Nav/Label", "kind.content=Menu"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase override"))
        #expect(!run.stderr.contains("{\"op\""))
    }

    @Test("A fill array with an unknown type is refused with the spelling that is wrong")
    func fillArrayWithUnknownType() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Cards",
            ##"kind.fills=[{"type":"solid","color":"#FFD166"}]"##, "--as", "claude-a"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        // The refusal must not list arrays as accepted and then say the value "is array".
        #expect(!run.stderr.contains("the value given is array"))
        #expect(run.stderr.contains("solid"))
        #expect(run.stderr.contains("[0]"))
        // It must name a literal the caller can paste instead — once, not in both
        // the accepted-shape half of the sentence and again in the remedy.
        #expect(run.stderr.components(separatedBy: ##"{"type":"color","color":"#FFD166"}"##).count == 2)
        #expect(try PenFileProbe(fixture.file).node("Canvas/Cards")?.frameFills == nil)
    }

    @Test("The fill array the refusal recommends is one the binary accepts")
    func fillArrayIsWritten() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Cards",
            ##"kind.fills=[{"type":"color","color":"#FFD166"}]"##, "--as", "claude-a"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(
            try PenFileProbe(fixture.file).node("Canvas/Cards")?.frameFills
                == .multiple([.color(PenFill.PenColorFill(color: .literal("#FFD166")))])
        )
    }

    @Test("The value rules a verb prints show a fill literal, not only scalars")
    func valueRulesShowAFill() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("set", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains(##"{"type":"color","color":"#FFD166"}"##))
    }

    @Test("kind.content set to a defined variable's bare name echoes the reference it became")
    func contentSetToDefinedVariableWarns() throws {
        let fixture = try CommandFixture(fixture: "content-variable.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Title", "kind.content=$v-muted", "--as", "ana"
        )

        #expect(run.status == 0)
        // The divergence is part of the answer, not an aside, so it is on stdout.
        #expect(run.stdout.contains(
            "kind.content resolved $v-muted as a reference to the color variable "
                + "v-muted — write \\$v-muted for the literal"
        ))
        #expect(run.stderr.isEmpty)
        // The write still stores what was asked for — the echo only says what the
        // stored form means, it does not change what `set` wrote.
        let probe = try PenFileProbe(fixture.file)
        let node = try #require(probe.node("Title"))
        guard case let .text(data) = node.kind, case let .variable(name)? = data.content else {
            Issue.record("Expected a variable reference")
            return
        }
        #expect(name == "v-muted")
    }

    @Test("kind.content set to \\$name stores the literal and echoes nothing")
    func contentSetToEscapedNameIsLiteral() throws {
        let fixture = try CommandFixture(fixture: "content-variable.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Title", ##"kind.content=\$v-muted"##, "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(!run.stdout.contains("resolved"))
        #expect(try PenFileProbe(fixture.file).node("Title")?.textContent == "$v-muted")
    }

    @Test("kind.content set to an undefined $name is not echoed about — it is not a variable")
    func contentSetToUndefinedNameIsNotWarned() throws {
        let fixture = try CommandFixture(fixture: "content-variable.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Title", "kind.content=$186", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(!run.stdout.contains("resolved"))
    }

    @Test("A set that stored what it was handed prints only the path and the revisions")
    func agreementPrintsThreeLines() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 3)
        #expect(run.stdoutLines[0] == "Canvas/Title  Ttl01")
        #expect(run.stdoutLines[1].hasPrefix("rev  "))
        #expect(run.stdoutLines[2].hasPrefix("document  "))
    }

    @Test("--json carries the post-state node the write left behind")
    func jsonCarriesThePostStateNode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--json"
        )

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        let node = try #require(report.node)
        #expect(node.id == "Ttl01")
        guard case let .text(data) = node.kind else {
            Issue.record("Expected a text node")
            return
        }
        #expect(data.content == .literal("Hello"))
    }

    @Test("--json answers with the node, its revision and the document's")
    func jsonOutput() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--json"
        )

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        #expect(report.path == "Canvas/Title")
        #expect(report.id == "Ttl01")
        #expect(report.nodeRevision?.count == 16)
        #expect(report.created == nil)
    }
}
