//
//  CopyTimesTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase cp --times N` repeats a copy N times in one write — the "repeat this
/// node" idiom that would otherwise cost N round trips and N colliding names.
@Suite("woodcase cp --times")
struct CopyTimesTests {
    @Test("--times 3 with a {n} name makes three addressable, distinct copies, in order")
    func copiesThreeTimesWithAPlaceholderName() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar {n}", "--times", "3"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        // 3 created roots (each a leaf, so one line each) + the document line.
        try #require(lines.count == 4)
        #expect(lines[0].hasPrefix("Bar 1  "))
        #expect(lines[1].hasPrefix("Bar 2  "))
        #expect(lines[2].hasPrefix("Bar 3  "))
        #expect(lines[3].hasPrefix("document  "))

        let probe = try PenFileProbe(fixture.file)
        let bar1 = try #require(probe.node("Canvas/Cards/Bar 1"))
        let bar2 = try #require(probe.node("Canvas/Cards/Bar 2"))
        let bar3 = try #require(probe.node("Canvas/Cards/Bar 3"))
        #expect(Set([bar1.id, bar2.id, bar3.id]).count == 3)
        #expect(probe.node("Canvas/Cards/First") != nil, "the source is untouched")

        let cards = try #require(probe.node("Canvas/Cards"))
        #expect(
            PenFileProbe.children(of: cards).map(\.common.name)
                == ["First", "Second", "Bar 1", "Bar 2", "Bar 3"]
        )
    }

    @Test("--at places every copy in order, starting at the given index")
    func placesCopiesInOrderAtAnIndex() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar {n}", "--times", "2", "--at", "0"
        )

        #expect(run.status == 0)
        let cards = try #require(try PenFileProbe(fixture.file).node("Canvas/Cards"))
        #expect(
            PenFileProbe.children(of: cards).map(\.common.name)
                == ["Bar 1", "Bar 2", "First", "Second"]
        )
    }

    @Test("Without the {n} placeholder, --times is refused and nothing is written")
    func refusedWithoutPlaceholder() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar", "--times", "3"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("{n}"))
        #expect(run.stderr.contains("common.name"))
        #expect(run.stderr.contains("Bar {n}"))
        let probe = try PenFileProbe(fixture.file)
        let cards = try #require(probe.node("Canvas/Cards"))
        #expect(PenFileProbe.children(of: cards).map(\.common.name) == ["First", "Second"])
    }

    @Test("With no common.name at all, --times is refused naming the placeholder")
    func refusedWithNoNameAssignment() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards", "--times", "3"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("{n}"))
    }

    @Test("--times 0 is a usage error")
    func rejectsNonPositiveTimes() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar {n}", "--times", "0"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("--times"))
        #expect(!run.stderr.contains("Unknown option"), "the flag itself must be recognized")
    }

    @Test("Each copy logs the same events one cp with a name would, and they share one batch")
    func onePerCopyInTheActivityLog() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar {n}", "--times", "3", "--as", "ana"
        )

        #expect(run.status == 0)
        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        // Every copy carries a name, so — exactly as a single `cp … common.name=X`
        // already does — each one is an insert plus the property set that names it.
        #expect(page.events.count == 6)
        #expect(page.events.count(where: { $0.op == .add }) == 3)
        #expect(page.events.count(where: { $0.op == .set }) == 3)
        let batches = Set(page.events.compactMap(\.batch))
        #expect(batches.count == 1, "every copy of one --times write shares a batch id")
    }

    @MainActor
    @Test("The revision guard applies once, before the first copy")
    func revisionGuardAppliesOnce() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let probe = try PenFileProbe(fixture.file)
        let cardsID = try #require(probe.node("Canvas/Cards")?.id)
        let cardsRevision = try #require(
            EditableDocument(from: PenParser.parse(contentsOf: fixture.file)).revision(of: cardsID)
        )

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar {n}", "--times", "3", "--rev", cardsRevision
        )

        #expect(run.status == 0)
        let cards = try #require(try PenFileProbe(fixture.file).node("Canvas/Cards"))
        #expect(PenFileProbe.children(of: cards).count == 5)
    }

    @Test("undo treats a --times write as one step, and --event still walks its rows")
    func undoReversesTimesInOneStep() throws {
        // Changed on 2026-09-07, with the ruling that one undo step is one transaction.
        // This test used to pin the opposite — "-n counts events, not copies", so
        // reversing this write took `undo -n 6` — which made undoing one command a
        // matter of counting its log rows first. The rows are unchanged; what changed
        // is that `undo` reads the batch id they already carried.
        let fixture = try CommandFixture(fixture: "batch.pen")
        #expect(
            try fixture.run(
                "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
                "common.name=Bar {n}", "--times", "3", "--as", "ana"
            ).status == 0
        )

        // 3 copies logged 6 events (an insert and a name-set per copy, sharing one
        // batch). --event is the older, finer step, and takes only the last of them:
        // the name-set that made the third copy "Bar 3".
        #expect(try fixture.run("undo", fixture.file.path, "--event", "--as", "ana").status == 0)
        let afterOneRow = try PenFileProbe(fixture.file)
        let cardsAfterOneRow = try #require(afterOneRow.node("Canvas/Cards"))
        #expect(
            PenFileProbe.children(of: cardsAfterOneRow).map(\.common.name)
                == ["First", "Second", "Bar 1", "Bar 2", "First"],
            "one --event step reverted the last copy's name-set, not the whole --times write"
        )

        // One plain undo finishes the command, however many rows of it are left.
        #expect(try fixture.run("undo", fixture.file.path, "--as", "ana").status == 0)
        let afterAll = try PenFileProbe(fixture.file)
        let cardsAfterAll = try #require(afterAll.node("Canvas/Cards"))
        #expect(PenFileProbe.children(of: cardsAfterAll).map(\.common.name) == ["First", "Second"])
    }

    @Test("--json reports every copy in the created tree")
    func jsonReportsEveryCopy() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Bar {n}", "--times", "3", "--json"
        )

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(WriteReport.self, from: Data(run.stdout.utf8))
        let created = try #require(report.created)
        #expect(created.map(\.name) == ["Bar 1", "Bar 2", "Bar 3"])
        #expect(Set(created.map(\.id)).count == 3)
    }
}
