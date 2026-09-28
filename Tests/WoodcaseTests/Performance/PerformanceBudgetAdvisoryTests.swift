//
//  PerformanceBudgetAdvisoryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// What ``PerformanceBudget/check(_:sourceLocation:)`` does with a measurement that is
/// over the limit.
///
/// The decision is the point: on the build the budgets are *stated* for, over is a
/// failure; on the default debug build it is only ever a note, however far over, because
/// a busy machine inflates every repetition together (Ben's ruling, 2026-09-28). Nothing
/// here measures anything — these are the rules, asserted directly, so a change to them
/// is a change somebody chose.
struct PerformanceBudgetAdvisoryTests {
    private let budget = PerformanceBudget(name: "a budget under test", release: .milliseconds(100))

    /// A sample whose minimum is exactly `elapsed`.
    private func sample(_ elapsed: Duration) -> PerformanceSample {
        PerformanceSample(elapsed: [elapsed, elapsed * 2])
    }

    @Test("A measurement inside the limit records nothing on any build")
    func insideTheLimitPasses() {
        budget.check(sample(budget.limit / 2))
    }

    /// Why the next two are traits and not `#require`: they describe the *advisory*
    /// build, so on a strict one they have nothing to say and must be **skipped**.
    /// `try #require(!isStrict)` reads like a guard but fails the test instead, which
    /// nobody noticed while `swift test -c release` could not run — the only two ways
    /// to reach a strict build were that and `WOODCASE_BUDGET_STRICT=1`. `.enabled(if:)`
    /// is the trait that actually skips.
    static let isAdvisoryBuild = !PerformanceBudget.isStrict

    @Test(
        "A debug measurement over the limit is only a note",
        .enabled(if: isAdvisoryBuild, "This case is about the advisory build.")
    )
    func overTheLimitIsAdvisoryUnderDebug() {
        budget.check(sample(budget.limit * 2))
    }

    @Test(
        "A debug measurement far past the limit is still only a note",
        .enabled(if: isAdvisoryBuild, "This case is about the advisory build.")
    )
    func farPastTheLimitIsAdvisoryUnderDebug() {
        budget.check(sample(budget.limit * 10))
    }

    @Test("The note says how far over the limit, and how to confirm it on release")
    func noteSaysHowFarAndWhatToRun() {
        let note = budget.advisory(sample(budget.limit * 3))
        #expect(note.hasPrefix("BUDGET-ADVISORY | a budget under test |"))
        #expect(note.contains("3.0×"))
        #expect(note.contains("swift test -c release --filter Performance"))
    }

    @Test("Strictness follows the build, and the environment can force it on")
    func strictnessFollowsTheBuild() {
        #expect(
            PerformanceBudget.isStrict
                == (PerformanceBudget.isOptimized
                    || ProcessInfo.processInfo
                    .environment[PerformanceBudget.strictEnvironmentVariable] != nil)
        )
    }
}
