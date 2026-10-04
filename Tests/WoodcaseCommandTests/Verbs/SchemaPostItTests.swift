//
//  SchemaPostItTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase schema postit` — the post-it metadata convention, printed from
/// ``PenPostIt/Key`` so the table and the refusal a misspelling raises agree.
@Suite("woodcase schema postit")
struct SchemaPostItTests {
    @Test("Lists every convention key, and the spellings of those that have them")
    func listsKeysAndSpellings() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "postit")

        #expect(run.status == 0, "schema postit failed: \(run.stderr)")
        for key in PenPostIt.Key.allCases {
            let row = run.stdoutLines.first { $0.contains("common.metadata.\(key.rawValue)") }
            #expect(row != nil, "the table omits \(key.rawValue)")
            for spelling in key.spellings {
                #expect(row?.contains(spelling) == true, "\(key.rawValue)'s row omits \(spelling)")
            }
        }
    }

    @Test("--json carries the same keys and spellings")
    func jsonCarriesKeys() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "postit", "--json")

        #expect(run.status == 0, "schema postit --json failed: \(run.stderr)")
        let report = try JSONDecoder().decode(SchemaPostItReport.self, from: Data(run.stdout.utf8))
        #expect(report.type == PenPostIt.typeValue)
        #expect(report.keys.map(\.key) == PenPostIt.Key.allCases.map { "common.metadata.\($0.rawValue)" })
        #expect(report.keys.first { $0.key == "common.metadata.state" }?.spellings == ["open", "resolved"])
    }

    @Test("The overview points at the convention")
    func overviewMentionsPostIt() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema")

        #expect(run.stdout.contains("woodcase schema postit"))
    }

    @Test("set refuses a misspelled kind with the suggestion and the code")
    func setRefusalNamesTheSuggestion() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let tag = try fixture.run(
            "set", fixture.file.path, "NNote", "common.metadata.type=postit", "--as", "t"
        )
        #expect(tag.status == 0, "tagging the note failed: \(tag.stderr)")

        let run = try fixture.run(
            "set", fixture.file.path, "NNote", "common.metadata.kind=questoin", "--as", "t"
        )

        #expect(run.status != 0)
        #expect(run.stderr.contains("question"), "the refusal reads \(run.stderr)")
        #expect(run.stderr.contains("did you mean"), "the refusal reads \(run.stderr)")
    }
}
