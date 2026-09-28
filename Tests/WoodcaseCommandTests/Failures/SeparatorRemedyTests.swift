//
//  SeparatorRemedyTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// What a dash-prefixed variable name gets told, and what it must not tell anyone else.
///
/// `--accent=#e0561a` is a variable name in every design-token file, and the parser
/// reads it as an option. The old answer — `Missing expected argument '<name=value>'` —
/// is true and says nothing, so the rule it broke is stated instead. The second half of
/// this suite is the part that matters: the sentence must not fire for a real option,
/// because then a typo and a token name would read the same.
@Suite("The `--` separator, taught where it is broken")
struct SeparatorRemedyTests {
    @Test("A dash-prefixed name names the `--` separator instead of a missing argument")
    func dashPrefixedNameNamesTheSeparator() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "--x=1", "--as", "ana")
        #expect(run.status == 2)
        #expect(
            run.stderr.contains("bare --"),
            "the refusal does not name the bare -- separator: \(run.stderr)"
        )
        #expect(
            !run.stderr.contains("Missing expected argument"),
            "the refusal still leads with the parser's own sentence: \(run.stderr)"
        )
        #expect(
            run.stderr.contains("-- --x=1"),
            "the refusal does not show the repaired command: \(run.stderr)"
        )
    }

    @Test("The repaired command the refusal prints is one that works")
    func theRepairedCommandRuns() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let refused = try fixture.run("vars", "set", fixture.file.path, "--x=1", "--as", "ana")
        #expect(refused.status == 2)

        let repaired = try fixture.run("vars", "set", fixture.file.path, "--as", "ana", "--", "--x=1")
        #expect(repaired.status == 0, "the form the refusal recommends does not run: \(repaired.stderr)")
        #expect(repaired.stdout.contains("--x"))
    }

    @Test("A real option that failed for another reason keeps the parser's own message")
    func aRealOptionIsNotMistakenForAName() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        // `--type=color` is `vars set`'s own option, correctly spelled; what is missing
        // is the assignment. Teaching the `--` rule here would send the caller to write
        // a variable literally named `--type`.
        let run = try fixture.run("vars", "set", fixture.file.path, "--type=color", "--as", "ana")
        #expect(run.status == 2)
        #expect(
            !run.stderr.contains("bare --"),
            "a correctly spelled option was read as a dash-prefixed variable name: \(run.stderr)"
        )
        #expect(run.stderr.contains("Missing expected argument"))
    }

    @Test("A line that already carries a `--` is left to the parser")
    func aTerminatedLineIsLeftAlone() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", fixture.file.path, "--as", "ana", "--")
        #expect(run.status == 2)
        #expect(!run.stderr.contains("bare --"), "the rule fired on a line that already obeys it")
    }

    @Test("`vars set --help` shows the separator with the example the topic shows")
    func helpShowsTheSeparator() throws {
        let fixture = try CommandFixture(fixture: "parser-variables.pen")
        let run = try fixture.run("vars", "set", "--help")
        #expect(run.status == 0)
        #expect(
            run.stdout.contains("woodcase vars set f.pen -- --accent=#e0561a"),
            "`vars set --help` does not show the -- separator example"
        )
    }
}
