//
//  GroupCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase group` and `woodcase ungroup`: adapters over the library's planners, so what
/// matters here is that they reach them, write one transaction and report the result.
@Suite("woodcase group and ungroup")
struct GroupCommandTests {
    @Test("Grouping two cards wraps them in the stack at the front-most one's slot, and ungroup undoes it")
    func groupThenUngroup() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let grouped = try fixture.run(
            "group", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards/Second", "--as", "ana", "--json"
        )
        #expect(grouped.status == 0, "\(grouped.stderr)")
        let report = try JSONDecoder().decode(GroupCommand.Report.self, from: Data(grouped.stdout.utf8))
        var document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        #expect(document.childIDs(of: "Crd01") == [report.id])
        #expect(document.childIDs(of: report.id) == ["Cd101", "Cd201"])

        let ungrouped = try fixture.run("ungroup", fixture.file.path, "#\(report.id)", "--as", "ana")
        #expect(ungrouped.status == 0, "\(ungrouped.stderr)")
        #expect(ungrouped.stdoutLines.first == "ungrouped Cd101, Cd201")
        document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        #expect(document.childIDs(of: "Crd01") == ["Cd101", "Cd201"])
    }

    @Test("--frame wraps in a frame that does not lay out its children")
    func frame() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("group", fixture.file.path, "Canvas/Title", "--frame", "--as", "ana", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(GroupCommand.Report.self, from: Data(run.stdout.utf8))
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        guard case let .frame(data)? = document.node(id: report.id)?.kind else {
            Issue.record("the wrapper is not a frame")
            return
        }
        #expect(data.layout == PenLayoutDirection.none)
    }

    @Test("Ungrouping a text is a usage failure that writes nothing")
    func ungroupRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("ungroup", fixture.file.path, "Canvas/Title", "--as", "ana")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("not a group or a frame"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }
}
