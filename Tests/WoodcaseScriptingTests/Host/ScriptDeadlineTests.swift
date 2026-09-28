//
//  ScriptDeadlineTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// The host's only runaway protection: a deadline every bridged call checks.
///
/// Asserted on outcome, never on elapsed time. The deadline handed in has *already*
/// passed, so the test says exactly one thing — a call past the deadline refuses — and
/// says it in microseconds. Wall-clock budgets are unreliable in the parallel suite
/// (`project/gotchas.md`, 2026-08-29), and a test that sleeps to prove a timeout is
/// measuring the machine.
@Suite("the script deadline")
struct ScriptDeadlineTests {
    /// A deadline that passed before the run began.
    private var expired: ContinuousClock.Instant {
        ContinuousClock.now.advanced(by: .seconds(-1))
    }

    @Test("a script past its deadline is refused on its next doc call")
    func aCallPastTheDeadlineRefuses() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text("doc.tree().length", name: "<argv>")],
            over: document,
            deadline: expired
        )
        let error = try #require(run.error)
        #expect(error.code == ScriptErrorCode.timeout)
        #expect(error.message.contains("--timeout"))
        #expect(run.commit == .rolledBack)
    }

    @Test("the timeout is catchable, and every later call refuses the same way")
    func theTimeoutIsCatchableButNotEscapable() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text(
                """
                const codes = [];
                for (let i = 0; i < 3; i++) {
                  try { doc.rev; } catch (e) { codes.push(e.code); }
                }
                codes
                """,
                name: "<argv>"
            )],
            over: document,
            deadline: expired
        )
        #expect(run.error == nil, "a caught timeout is not a failed run")
        #expect(run.result == .array([.string("timeout"), .string("timeout"), .string("timeout")]))
    }

    @Test("a script that calls nothing runs to the end even past its deadline")
    func pureComputationIsNotStopped() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text("1 + 1", name: "<argv>")],
            over: document,
            deadline: expired
        )
        #expect(run.error == nil, "the deadline binds bridged calls; stopping a pure loop is the CLI's job")
        #expect(run.result == .int(2))
    }

    @Test("a budget in the future does not refuse")
    func aLiveBudgetDoesNotRefuse() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text("doc.tree().length", name: "<argv>")],
            over: document,
            timeout: .seconds(600)
        )
        #expect(run.error == nil)
        #expect(run.result == .int(9))
    }
}
