//
//  IconsCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

struct IconsCommandTests {
    /// `icons` reads no .pen file, but the fixture still gives it a binary and a
    /// throwaway `$WOODCASE_HOME` to run in.
    private func fixture() throws -> CommandFixture {
        try CommandFixture(fixture: "batch.pen")
    }

    @Test("With no query, every name in the library is printed, sorted")
    func noQueryListsEverySortedName() throws {
        let run = try fixture().run("icons", "lucide")
        #expect(run.status == 0)
        let lines = run.stdoutLines
        #expect(lines == lines.sorted())
        #expect(lines.contains("check"))
        #expect(lines.contains("circle-check"))
        #expect(lines.count > 1000)
    }

    @Test("A query lists check, circle-check and their kin")
    func queryListsCheckAndKin() throws {
        let run = try fixture().run("icons", "lucide", "check")
        #expect(run.status == 0)
        let lines = run.stdoutLines
        #expect(lines.first == "check")
        #expect(lines.contains("circle-check"))
        #expect(lines.allSatisfy { $0.contains("check") })
    }

    @Test("A renamed icon's query proposes the token-overlapping replacement first")
    func renamedIconProposesReplacement() throws {
        let run = try fixture().run("icons", "lucide", "check-circle-2")
        #expect(run.status == 0)
        #expect(run.stdoutLines.first == "circle-check")
    }

    @Test("--json prints a JSON array of names, ranked the same way")
    func jsonPrintsArray() throws {
        let run = try fixture().run("icons", "lucide", "check", "--json")
        #expect(run.status == 0)
        let names = try JSONDecoder().decode([String].self, from: Data(run.stdout.utf8))
        #expect(names.first == "check")
    }

    @Test("A query matching nothing prints nothing and exits 1, the clean negative")
    func noMatchIsCleanNegative() throws {
        let run = try fixture().run("icons", "lucide", "xylophone-emoji-9000")
        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
    }

    @Test("An unknown library is refused at exit 2, naming the known ones")
    func unknownLibraryIsUsageError() throws {
        let run = try fixture().run("icons", "not-a-real-library")
        #expect(run.status == 2)
        #expect(run.stderr.contains("not-a-real-library"))
        #expect(run.stderr.contains("lucide"))
    }
}
