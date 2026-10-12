//
//  TreeMetadataColumnTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `--props` reads one metadata key by a deep key — the same form `set` writes — so
/// `tree` and `find` can show who wrote a note or which task it belongs to.
@Suite("woodcase tree reads metadata columns")
struct TreeMetadataColumnTests {
    @Test("tree --props common.metadata.woodcase.leaf prints values, from either spelling")
    func namespacedLeafColumn() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props", "common.metadata.woodcase.leaf")

        #expect(run.status == 0, "tree refused: \(run.stderr)")
        #expect(run.stderr.isEmpty, "stderr: \(run.stderr)")
        let plan = try #require(run.stdoutLines.first { $0.hasSuffix("Nte01") })
        let old = try #require(run.stdoutLines.first { $0.hasSuffix("Nte02") })
        #expect(plan.contains("Wq5asV"), "Nte01 reads \(plan)")
        #expect(old.contains("pODcm0"), "Nte02 reads \(old)")
    }

    @Test("tree --props common.metadata.leaf, the old spelling, reads where it is Woodcase's")
    func oldSpellingLeafColumn() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props", "common.metadata.leaf")

        #expect(run.status == 0, "tree refused: \(run.stderr)")
        let old = try #require(run.stdoutLines.first { $0.hasSuffix("Nte02") })
        #expect(old.contains("pODcm0"), "Nte02 reads \(old)")
    }

    @Test("An absent metadata key reads as null in --json")
    func absentKeyIsNull() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run(
            "tree", fixture.file.path, "Nte03", "--props", "common.metadata.woodcase.author", "--json"
        )

        #expect(run.status == 0, "tree refused: \(run.stderr)")
        #expect(run.stdout.contains(#""common.metadata.woodcase.author" : null"#), "stdout: \(run.stdout)")
    }

    @Test("find reads a metadata column as r.props[…]")
    func findByAuthor() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run(
            "find", fixture.file.path,
            #"r => r.props["common.metadata.woodcase.author"] === "claude""#,
            "--props", "common.metadata.woodcase.author"
        )

        #expect(run.status == 0, "find refused: \(run.stderr)")
        let ids = run.stdoutLines.dropFirst(2).compactMap { $0.split(separator: " ").last.map(String.init) }
        #expect(ids == ["Nte02", "Cm02", "Cm05"])
    }
}
