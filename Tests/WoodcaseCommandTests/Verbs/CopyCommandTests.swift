//
//  CopyCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase cp` duplicates a subtree with fresh ids — and the properties it is
/// given have to land on the copy, never on the thing that was copied.
@Suite("woodcase cp")
struct CopyCommandTests {
    @Test("A subtree is copied with fresh ids, and the tree of them comes back")
    func copiesASubtree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Canvas/Cards/First", "Board", "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        try #require(lines.count == 3)
        #expect(lines[0].hasPrefix("First  "))
        #expect(!lines[0].hasSuffix("Cd101"))

        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Board/First") != nil)
        #expect(probe.node("Canvas/Cards/First") != nil)

        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.contains { $0.op == .add })
    }

    @Test("A name-path override retitles the copy and leaves the original untouched")
    func namePathOverrideHitsTheCopy() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas", "document",
            "common.name=Copy", "Title/kind.content=Copied"
        )

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Copy/Title")?.textContent == "Copied")
        #expect(probe.node("Canvas/Title")?.textContent == "Canvas")
    }

    @Test("A name-path override that names nothing in the copy is refused, and nothing is written")
    func unknownNamePathOverride() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas", "document", "Nowhere/kind.content=Copied"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nowhere"))
        #expect(try PenFileProbe(fixture.file).roots.count == 3)
    }

    @Test("Copying a reusable component makes an instance of it, as Pen does")
    func copyingAComponentInstantiatesIt() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Component", "Canvas")

        #expect(run.status == 0)
        let copy = try #require(try PenFileProbe(fixture.file).node("Canvas/Component"))
        guard case let .ref(data) = copy.kind else {
            Issue.record("the copy is a \(copy.kind.typeName), not a component instance")
            return
        }
        #expect(data.ref == "Cmp01")
    }

    @Test("A root-level copy without coordinates lands in empty space")
    func autoPlacesAtTheRoot() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Canvas/Cards", "document", "common.name=Loose")

        #expect(run.status == 0)
        let loose = try #require(try PenFileProbe(fixture.file).root(named: "Loose"))
        #expect(loose.literalX == 800)
    }

    @Test("A root-level copy of a root lands in empty space, not on top of its source")
    func rootCopyDoesNotLandOnItsSource() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Board", "document", "common.name=Loose")

        #expect(run.status == 0)
        let loose = try #require(try PenFileProbe(fixture.file).root(named: "Loose"))
        // Board is at (500, 40) — coordinates that describe the source, not the copy.
        #expect(loose.literalX == 800)
        #expect(loose.literalY == 0)
    }

    @Test("The placement note names the copy, not the source, when the same call renames it")
    func placementNoteNamesTheCopy() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Canvas/Cards", "document", "common.name=Loose")

        #expect(run.status == 0)
        #expect(run.stdout.contains("Loose was placed at"))
        #expect(!run.stdout.contains("Cards was placed at"))
    }

    @Test("The placement note still names the source when the copy keeps the source's name")
    func placementNoteNamesTheSourceWhenNotRenamed() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Canvas/Cards", "document")

        #expect(run.status == 0)
        #expect(run.stdout.contains("Cards was placed at"))
    }

    @Test("A source that resolves to nothing is a usage error naming the address")
    func unknownSourceIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("cp", fixture.file.path, "Nowhere", "Board")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nowhere"))
        #expect(run.stderr.contains("no node"))
    }
}
