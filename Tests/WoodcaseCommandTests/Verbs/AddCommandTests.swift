//
//  AddCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase add` drives the binary end to end: the subtree file goes in, the
/// name → id tree comes out, and the activity log records it.
@Suite("woodcase add")
struct AddCommandTests {
    /// Writes a subtree file beside the fixture and returns its path.
    private func subtree(_ json: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent("subtree-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test("A subtree lands under its parent and the ids come back as a tree")
    func addsASubtree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(
            #"{"type":"frame","name":"Hero","width":100,"height":40,"#
                + #""children":[{"type":"text","name":"Caption","content":"hi"}]}"#,
            in: fixture
        )

        let run = try fixture.run("add", fixture.file.path, "Canvas", "-F", file, "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("Hero  "))
        #expect(lines[1].hasPrefix("  Caption  "))
        #expect(lines[2].hasPrefix("rev  "))
        #expect(lines[3].hasPrefix("document  "))

        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Canvas/Hero/Caption")?.textContent == "hi")

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.count == 1)
        #expect(page.events.first?.op == .add)
        #expect(page.events.first?.identity == "ana")
    }

    @Test("--at puts the new node where it was asked to go")
    func addsAtAnIndex() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"type":"frame","name":"Third","width":10,"height":10}"#, in: fixture)

        let run = try fixture.run("add", fixture.file.path, "Canvas/Cards", "-F", file, "--at", "0")

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        let cards = try #require(probe.node("Canvas/Cards"))
        #expect(PenFileProbe.children(of: cards).map(\.common.name) == ["Third", "First", "Second"])
    }

    @Test("A root-level add without coordinates lands in empty space, not at 0,0")
    func autoPlacesAtTheRoot() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"type":"frame","name":"Loose","width":100,"height":100}"#, in: fixture)

        let run = try fixture.run("add", fixture.file.path, "document", "-F", file)

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        let loose = try #require(probe.root(named: "Loose"))
        // Board's right edge is 700, and the gap is 100.
        #expect(loose.literalX == 800)
        #expect(loose.literalY == 0)
    }

    @Test("An unnamed node in the subtree is refused, and the message says to name it")
    func unnamedNodeIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(
            #"{"type":"frame","name":"Hero","children":[{"type":"text","content":"hi"}]}"#,
            in: fixture
        )

        let run = try fixture.run("add", fixture.file.path, "Canvas", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("has no name"))
        #expect(run.stderr.contains("\"name\""))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Hero") == nil)
    }

    @Test("An id in the subtree is kept, and the ids left out are drawn")
    func keepsASuppliedID() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(
            #"{"id":"Hero1","type":"frame","name":"Hero","width":100,"height":40,"#
                + #""children":[{"type":"text","name":"Caption","content":"hi"}]}"#,
            in: fixture
        )

        let run = try fixture.run("add", fixture.file.path, "Canvas", "-F", file, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        let hero = try #require(report.created?.first)
        #expect(hero.id == "Hero1")
        let caption = try #require(hero.children.first)
        #expect(caption.id != "Hero1")
        #expect(!caption.id.isEmpty)

        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Canvas/Hero")?.id == "Hero1")
    }

    @Test("A supplied id the file already uses is refused, and the message says to leave it out")
    func collidingSuppliedIDIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"id":"Cd101","type":"frame","name":"Hero","width":10,"height":10}"#, in: fixture)

        let run = try fixture.run("add", fixture.file.path, "Canvas", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Cd101"))
        #expect(run.stderr.contains("\"id\""))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Hero") == nil)
    }

    @Test("A subtree file that is not there is a target failure naming the path")
    func missingSubtreeFile() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("add", fixture.file.path, "Canvas", "-F", "/nowhere/subtree.json")

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("/nowhere/subtree.json"))
    }

    @Test("A parent that resolves to nothing is a usage error naming the address")
    func unknownParent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"type":"frame","name":"Hero","width":10,"height":10}"#, in: fixture)

        let run = try fixture.run("add", fixture.file.path, "Nowhere", "-F", file)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nowhere"))
    }

    @Test("--json answers with the created ids and the document revision")
    func jsonOutput() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try subtree(#"{"type":"frame","name":"Hero","width":10,"height":10}"#, in: fixture)

        let run = try fixture.run("add", fixture.file.path, "Canvas", "-F", file, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        #expect(report.created?.first?.name == "Hero")
        // Optional since `--dry-run`, which has no revision to name; a real write always
        // has one.
        #expect(report.documentRevision?.count == 16)
    }
}
