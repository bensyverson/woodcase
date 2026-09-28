//
//  JsWatchdogTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The last line of defence: a script that never calls back into Swift.
///
/// The host's deadline is checked by every bridged call, so it bounds every script that
/// does work. `while (true) {}` does no work the host can see, and JavaScriptCore
/// publishes no execution-time limit to ask for, so the CLI ends the process itself.
///
/// Every assertion here is about the **outcome** — the sentence, the exit code, the
/// file's bytes — and never about elapsed time: wall-clock assertions are unreliable in
/// the parallel suite (`project/gotchas.md`, 2026-08-29). The bound that keeps a broken
/// watchdog from hanging the suite is ``CommandFixture/runBudget``, which is two orders
/// of magnitude above the one-second timeout these runs are given.
@Suite("woodcase js watchdog")
struct JsWatchdogTests {
    /// Writes a script beside the fixture and answers with its path.
    private func script(_ body: String, named name: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url.path
    }

    @Test("A loop that never calls doc exits 3 with the sentence, and the file is untouched")
    func aRunawayLoopIsEndedAndSaysSo() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script("while (true) {}\n", named: "spin.js", in: fixture)

        let run = try fixture.run(
            "js", fixture.file.path, "-F", path, "--timeout", "1", "--as", "ana"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("script ran past 1 s; nothing was written"))
        try #expect(Data(contentsOf: fixture.file) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }

    @Test("A runaway that wrote first still writes nothing: the transaction never committed")
    func aRunawayAfterAWriteKeepsNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script(
            "doc.set('Canvas/Title', { 'kind.content': 'Doomed' });\nwhile (true) {}\n",
            named: "spin.js", in: fixture
        )

        let run = try fixture.run(
            "js", fixture.file.path, "-F", path, "--timeout", "1", "--as", "ana"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A script that loops while calling doc is refused by the host's own deadline, exit 3")
    func aBridgedLoopHitsTheDeadline() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script("while (true) { doc.tree(); }\n", named: "poll.js", in: fixture)

        let run = try fixture.run(
            "js", fixture.file.path, "-F", path, "--timeout", "1", "--as", "ana"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A script that finishes inside its budget is not touched by the watchdog")
    func aQuickScriptIsLeftAlone() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("doc.tree().length", named: "quick.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--timeout", "1")

        #expect(run.status == 0)
        #expect(!run.stderr.contains("ran past"))
    }

    @Test("A --timeout that is not a positive number of seconds is a usage error")
    func aNonsensicalTimeoutIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("doc.tree().length", named: "quick.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--timeout", "0")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--timeout"))
    }
}
