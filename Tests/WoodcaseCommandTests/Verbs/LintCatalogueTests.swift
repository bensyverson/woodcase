//
//  LintCatalogueTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `lint --list` and `lint --summary`: the two reads that are about the checks rather
/// than about one file's findings.
///
/// `--list` is the catalogue — every check id with the one line saying what it looks
/// for — and it has no preconditions, so it answers with no file at all. `--summary`
/// is the same run of the same checks reported as counts instead of lines.
struct LintCatalogueTests {
    // MARK: - --list

    @Test("--list prints every check, one per line, with no file")
    func listPrintsEveryCheck() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list")
        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        #expect(lines.count == LintCheck.allCases.count)
        for check in LintCheck.allCases {
            #expect(lines.contains { $0.contains(" \(check.rawValue)  ") })
        }
    }

    @Test("--list carries each check's one-line description")
    func listCarriesSummaries() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list")
        for check in LintCheck.allCases {
            #expect(run.stdout.contains(check.summary))
        }
    }

    @Test("--list --json is an array with an object per check")
    func listJSON() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list", "--json")
        #expect(run.status == 0)
        let rows = try JSONDecoder().decode([[String: String]].self, from: Data(run.stdout.utf8))
        #expect(rows.count == LintCheck.allCases.count)
        let byID = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row["check"].map { ($0, row) }
        })
        for check in LintCheck.allCases {
            #expect(byID[check.rawValue]?["summary"] == check.summary)
            #expect(byID[check.rawValue]?["severity"] == check.severity.rawValue)
        }
    }

    @Test("--list composes with --exclude, which drops the row")
    func listComposesWithExclude() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list", "--exclude", "clipped")
        #expect(run.status == 0)
        #expect(run.stdoutLines.count == LintCheck.allCases.count - 1)
        #expect(!run.stdout.contains(" clipped  "))
    }

    @Test("--list composes with --severity, which keeps only the errors")
    func listComposesWithSeverity() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list", "--severity", "error")
        #expect(run.status == 0)
        #expect(!run.stdout.contains("warning "))
        #expect(run.stdoutLines.count == LintCheck.allCases.count(where: { $0.severity == .error }))
    }

    // MARK: - Refusals

    @Test("--list with a file is a usage error: the catalogue reads no file")
    func listWithAFileIsAUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--list")
        #expect(run.status == 2)
        #expect(run.stderr.contains("--list"))
        #expect(run.stdout.isEmpty)
    }

    @Test("--list with --summary is a usage error naming both")
    func listWithSummaryIsAUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list", "--summary")
        #expect(run.status == 2)
        #expect(run.stderr.contains("--list"))
        #expect(run.stderr.contains("--summary"))
    }

    @Test("--list with --theme is a usage error: no file settles")
    func listWithThemeIsAUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", "--list", "--theme", "mode=dark")
        #expect(run.status == 2)
        #expect(run.stderr.contains("--theme"))
    }

    @Test("lint with no file and no --list is a usage error naming the argument")
    func noFileIsAUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint")
        #expect(run.status == 2)
        #expect(run.stderr.contains(".pen"))
    }

    // MARK: - --summary

    @Test("--summary prints one row per check that fired, with its count")
    func summaryCounts() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--summary")
        #expect(run.status == 1)
        #expect(run.stdoutLines == ["warning clipped  2"])
    }

    @Test("--summary omits a check that found nothing")
    func summaryOmitsZeroRows() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--summary")
        #expect(run.stdoutLines.count == 1)
        #expect(!run.stdout.contains("broken-ref"))
    }

    @Test("--summary --json is an object keyed by check id")
    func summaryJSON() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--summary", "--json")
        #expect(run.status == 1)
        let counts = try JSONDecoder().decode([String: Int].self, from: Data(run.stdout.utf8))
        #expect(counts == ["clipped": 2])
    }

    @Test("A clean file's summary says nothing and exits 0")
    func cleanSummary() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--summary")
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test("A clean file's summary JSON is an empty object")
    func cleanSummaryJSON() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--summary", "--json")
        #expect(run.status == 0)
        #expect(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "{}")
    }

    @Test("--summary composes with --exclude, which empties the report")
    func summaryComposesWithExclude() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--summary", "--exclude", "clipped")
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test("--summary composes with a node argument, which scopes the counts")
    func summaryComposesWithScope() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "Root/Overflows", "--summary")
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }
}
