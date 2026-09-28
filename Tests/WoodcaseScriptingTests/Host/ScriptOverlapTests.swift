//
//  ScriptOverlapTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// A script that leaves one artboard sitting on another says so on the run's own
/// timeline.
///
/// The warning used to be the `js` verb's: it took the pairs before the run and diffed
/// them after, so a library caller running ``ScriptHost`` directly — Penumbra — never saw
/// an overlap a script had created. The diff is the library's now and the host records
/// it, so both callers learn the same fact from the same place.
@Suite("a script's root overlaps")
struct ScriptOverlapTests {
    /// Runs one script over a fixture, naming a file so the remedy is a command.
    private func run(_ text: String, over fixture: String = "lint/artboard-overlap-clean.pen") throws -> ScriptRun {
        let document = try ScriptFixture.document(fixture)
        return ScriptHost.run(
            [.text(text, name: "<argv>")],
            over: document,
            remedy: .command(file: "design.pen")
        )
    }

    /// The findings a run recorded, in order.
    private func overlaps(of run: ScriptRun) -> [LintFinding] {
        run.events.compactMap {
            if case let .overlap(finding) = $0 { finding } else { nil }
        }
    }

    // MARK: - What a run records

    @Test("a script that slides one artboard onto another records one overlap, as the verbs print it")
    func aCreatedOverlapIsRecorded() throws {
        let run = try run("doc.set('Chk01', { 'common.x': 100 })")

        #expect(run.error == nil)
        let findings = overlaps(of: run)
        #expect(findings.count == 1)
        #expect(
            LintFormatter.text(findings) == "warning artboard-overlap  Checkout (Chk01)  "
                + "100,0 200×100 overlaps Home (Home1) 0,0 200×100. Artboards do not overlap: "
                + "run `woodcase set design.pen Chk01 common.x=300` to put it clear by 100pt."
        )
    }

    @Test("a script that breaks the layout and repairs it records nothing")
    func aRepairedOverlapIsNotRecorded() throws {
        let run = try run(
            """
            doc.set('Chk01', { 'common.x': 100 });
            doc.set('Chk01', { 'common.x': 200 });
            """
        )

        #expect(run.error == nil)
        #expect(overlaps(of: run).isEmpty)
    }

    @Test("an overlap the script did not create is left to lint")
    func aPreexistingOverlapIsNotRepeated() throws {
        let run = try run(
            "doc.set('Set01', { 'common.name': 'Preferences' })",
            over: "lint/artboard-overlap-trips.pen"
        )

        #expect(run.error == nil)
        #expect(overlaps(of: run).isEmpty)
    }

    @Test("a read-only script records nothing")
    func aReadOnlyRunIsSilent() throws {
        let run = try run("doc.tree().length")

        #expect(run.error == nil)
        #expect(overlaps(of: run).isEmpty)
    }

    @Test("a run that ended in an error warns about nothing, because nothing was written")
    func aRolledBackRunIsSilent() throws {
        let run = try run(
            """
            doc.set('Chk01', { 'common.x': 100 });
            throw new Error('no');
            """
        )

        #expect(run.error != nil)
        #expect(run.commit == .rolledBack)
        #expect(overlaps(of: run).isEmpty)
    }

    @Test("the sink sees the overlap as it is recorded, in the order the timeline holds it")
    func theSinkSeesIt() throws {
        let document = try ScriptFixture.document("lint/artboard-overlap-clean.pen")
        var seen: [ScriptRun.Event] = []
        let run = ScriptHost.run(
            [.text("doc.set('Chk01', { 'common.x': 100 })", name: "<argv>")],
            over: document,
            remedy: .command(file: "design.pen"),
            sink: { seen.append($0) }
        )

        #expect(seen.count == run.events.count)
        #expect(overlaps(of: run).count == 1)
        if case .overlap = seen.last {} else {
            Issue.record("the sink's last event was \(String(describing: seen.last))")
        }
    }

    // MARK: - The library's own diff

    @Test("a caller with no file on disk gets the placeholder the linter uses")
    func aScriptDialectNamesNoFile() throws {
        let document = try ScriptFixture.document("lint/artboard-overlap-clean.pen")
        let run = ScriptHost.run(
            [.text("doc.set('Chk01', { 'common.x': 100 })", name: "<argv>")],
            over: document
        )

        let finding = try #require(overlaps(of: run).first)
        #expect(finding.message.contains("woodcase set <file> Chk01"))
    }
}
