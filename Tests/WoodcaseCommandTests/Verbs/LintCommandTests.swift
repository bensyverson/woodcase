//
//  LintCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

struct LintCommandTests {
    @Test("A clean file prints nothing and exits 0")
    func cleanFileExitsZero() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path)
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
    }

    @Test("A clean file's JSON form is an empty array")
    func cleanFileJSON() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--json")
        #expect(run.status == 0)
        #expect(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "[]")
    }

    @Test("Findings print one line each and exit 1, the clean negative")
    func findingsExitOne() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path)
        let lines = run.stdoutLines
        #expect(run.status == 1)
        #expect(lines.count == 2)
        #expect(lines.first?.hasPrefix("warning clipped  Root/Overflows (Ovr01)  ") == true)
        #expect(lines.dropFirst().first?.hasPrefix("warning clipped  Root/Outside (Out01)  ") == true)
    }

    @Test("--json prints the findings array a caller can decode")
    func findingsAsJSON() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--json")
        #expect(run.status == 1)
        let findings = try JSONDecoder().decode([LintFinding].self, from: Data(run.stdout.utf8))
        #expect(findings.map(\.check) == [.clipped, .clipped])
        #expect(findings.map(\.path) == ["Root/Overflows", "Root/Outside"])
    }

    @Test("A node argument scopes the lint to that subtree")
    func nodeArgumentScopes() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let whole = try fixture.run("lint", fixture.file.path, "Root")
        #expect(whole.status == 1)
        #expect(whole.stdoutLines.count == 2)

        let leaf = try fixture.run("lint", fixture.file.path, "Root/Overflows")
        #expect(leaf.status == 0)
        #expect(leaf.stdout.isEmpty)
    }

    @Test("A node that names nothing is a usage error naming the address")
    func unknownNodeIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "Nope")
        #expect(run.status == 2)
        #expect(run.stderr.contains("Nope"))
        #expect(run.stdout.isEmpty)
    }

    @Test("A missing file is a target failure, not a usage error")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.root.appendingPathComponent("nope.pen").path)
        #expect(run.status == 4)
    }

    @Test("A malformed --theme pin is a usage error")
    func malformedThemeIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--theme", "mode")
        #expect(run.status == 2)
        #expect(run.stderr.contains("mode"))
    }

    @Test("A theme pin is accepted and lints that theme")
    func themePinIsAccepted() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--theme", "mode=dark")
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test("The pipeline's own diagnostics are reported as document-level findings")
    func pipelineDiagnosticsAreReported() throws {
        let fixture = try CommandFixture(fixture: "lint/pipeline-trips.pen")
        let run = try fixture.run("lint", fixture.file.path)
        let lines = run.stdoutLines
        #expect(run.status == 1)
        #expect(lines.count == 1)
        #expect(lines.first?.hasPrefix("warning pipeline  document  ") == true)
        #expect(lines.first?.contains("2.13") == true)
    }

    @Test("A file that is not a .pen document is a target failure")
    func unparsableFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let broken = fixture.root.appendingPathComponent("broken.pen")
        try "not json".write(to: broken, atomically: true, encoding: .utf8)
        let run = try fixture.run("lint", broken.path)
        #expect(run.status == 4)
    }

    // MARK: - --exclude

    @Test("--exclude drops findings from that check, and exits 0 when none remain")
    func excludeDropsOneCheck() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--exclude", "clipped")
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test("--exclude is repeatable, and drops only the named checks")
    func excludeIsRepeatable() throws {
        let fixture = try CommandFixture(fixture: "lint/mixed-severity-trips.pen")
        let run = try fixture.run(
            "lint", fixture.file.path, "--exclude", "clipped", "--exclude", "broken-ref"
        )
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test("--exclude leaves other checks' findings alone — the everything-but-clipped case")
    func excludeLeavesOtherChecksAlone() throws {
        let fixture = try CommandFixture(fixture: "lint/mixed-severity-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--exclude", "clipped")
        #expect(run.status == 1)
        let lines = run.stdoutLines
        #expect(lines.count == 1)
        #expect(lines.first?.hasPrefix("error broken-ref  ") == true)
    }

    @Test("An unknown --exclude check id is a usage error listing the valid ones")
    func excludeUnknownCheckIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--exclude", "bogus-check")
        #expect(run.status == 2)
        #expect(run.stderr.contains("bogus-check"))
        #expect(run.stderr.contains("clipped"))
        #expect(run.stdout.isEmpty)
    }

    // MARK: - --severity

    @Test("--severity error drops warning findings, keeping errors")
    func severityErrorDropsWarnings() throws {
        let fixture = try CommandFixture(fixture: "lint/mixed-severity-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--severity", "error")
        #expect(run.status == 1)
        let lines = run.stdoutLines
        #expect(lines.count == 1)
        #expect(lines.first?.hasPrefix("error broken-ref  ") == true)
    }

    @Test("--severity error on an all-warning file exits 0 with nothing to print")
    func severityErrorOnAllWarningsIsClean() throws {
        let fixture = try CommandFixture(fixture: "lint/clipped-trips.pen")
        let run = try fixture.run("lint", fixture.file.path, "--severity", "error")
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    @Test("With no --severity, warnings and errors both print, as before")
    func noSeverityFilterKeepsEverything() throws {
        let fixture = try CommandFixture(fixture: "lint/mixed-severity-trips.pen")
        let run = try fixture.run("lint", fixture.file.path)
        #expect(run.status == 1)
        #expect(run.stdoutLines.count == 2)
    }

    @Test("An unknown --severity level is a usage error listing the valid ones")
    func severityUnknownLevelIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "lint/clean.pen")
        let run = try fixture.run("lint", fixture.file.path, "--severity", "critical")
        #expect(run.status == 2)
        #expect(run.stderr.contains("critical"))
        #expect(run.stderr.contains("warning"))
        #expect(run.stdout.isEmpty)
    }

    // MARK: - --exclude and --severity together

    @Test("--exclude and --severity compose")
    func excludeAndSeverityCompose() throws {
        let fixture = try CommandFixture(fixture: "lint/mixed-severity-trips.pen")
        let run = try fixture.run(
            "lint", fixture.file.path, "--exclude", "broken-ref", "--severity", "error"
        )
        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    // MARK: - Codegen readiness

    @Test("A _props path that resolves to nothing prints the set command that fixes it")
    func codegenPropPathLineNamesTheFix() throws {
        let fixture = try CommandFixture(fixture: "lint/codegen-prop-path-trips.pen")
        let run = try fixture.run("lint", fixture.file.path)
        #expect(run.status == 1)
        let line = run.stdoutLines.first { $0.contains("codegen-prop-path") && $0.contains("`title`") }
        #expect(line?.hasPrefix("error codegen-prop-path  Card (Cmp01)  ") == true)
        #expect(line?.contains("woodcase set <file> Cmp01 common.metadata._props.title=") == true)
    }

    @Test("An unmapped instance override prints the _props entry that would map it")
    func codegenUnmappedOverrideLineNamesTheFix() throws {
        let fixture = try CommandFixture(fixture: "lint/codegen-unmapped-override-trips.pen")
        let run = try fixture.run("lint", fixture.file.path)
        #expect(run.status == 1)
        let line = run.stdoutLines.first { $0.contains("codegen-unmapped-override") }
        #expect(line?.hasPrefix("warning codegen-unmapped-override  Root/Chip (Rf001)  ") == true)
        #expect(line?.contains("woodcase set <file> Cmp01 common.metadata._props.subtitle=Subtitle") == true)
    }
}
