//
//  SchemaPostItTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase schema postit` — the post-it metadata convention, printed from
/// ``PenPostIt/keys`` so the table and the refusal a misspelling raises agree.
@Suite("woodcase schema postit")
struct SchemaPostItTests {
    @Test("Lists every convention key, and the spellings of those that have them")
    func listsKeysAndSpellings() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema", "postit")

        #expect(run.status == 0, "schema postit failed: \(run.stderr)")
        for key in PenPostIt.keys {
            // Printed at its note.* alias since DPY8DH.
            let row = run.stdoutLines.first { $0.contains("\(key.propertyPath) ") }
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
        // note.* aliases since DPY8DH; the raw keys stay accepted.
        #expect(report.keys.map(\.key) == PenPostIt.keys.map { "note.\($0.rawValue)" })
        #expect(report.keys.first { $0.key == "note.state" }?.spellings == ["open", "resolved"])
        let fontSize = PenMetadata.WoodcaseKey.fontSize.constraint?.summary
        #expect(fontSize != nil)
        #expect(report.keys.first { $0.key == "note.fontSize" }?.takes == fontSize)
        #expect(report.keys.first { $0.key == "note.letterSpacing" }?.takes == "any number")
    }

    @Test("The overview points at the convention")
    func overviewMentionsPostIt() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("schema")

        #expect(run.stdout.contains("woodcase schema postit"))
    }

    @Test("set refuses a misspelled state with the suggestion and the code")
    func setRefusalNamesTheSuggestion() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "NNote", "common.metadata.woodcase.state=reslved", "--as", "t"
        )

        #expect(run.status != 0)
        // The suggestion keeps the caller's spelling: raw here, note.state for an alias write.
        #expect(run.stderr.contains("common.metadata.woodcase.state=resolved"), "the refusal reads \(run.stderr)")
        #expect(run.stderr.contains("did you mean"), "the refusal reads \(run.stderr)")
    }
}
