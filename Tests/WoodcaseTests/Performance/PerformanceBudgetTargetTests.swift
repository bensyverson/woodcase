//
//  PerformanceBudgetTargetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

/// What ``PerformanceBudget/check(_:sourceLocation:)`` does with a budget that is a
/// *target* — a ceiling a design has set for code that has not landed yet.
///
/// The layout-edit budgets are the first of these: the node-granular engine they
/// describe is later work, so today's root-granular figures sit far over them. A target
/// must still print its `BUDGET` line (that is how the baseline is recorded) and must
/// never fail a run, on any build, until the leaf that meets it flips it to enforced.
struct PerformanceBudgetTargetTests {
    private let target = PerformanceBudget(
        name: "a target under test",
        release: .milliseconds(1),
        standing: .target
    )

    /// A sample whose minimum is exactly `elapsed`.
    private func sample(_ elapsed: Duration) -> PerformanceSample {
        PerformanceSample(elapsed: [elapsed, elapsed * 2])
    }

    @Test("A budget is enforced unless it says it is a target")
    func enforcedByDefault() {
        let budget = PerformanceBudget(name: "a committed budget", release: .milliseconds(100))
        #expect(budget.standing == .enforced)
    }

    @Test(
        "A target over its limit is only a note, even on a strict build",
        .enabled(if: PerformanceBudget.isStrict, "Only a strict build would fail an enforced budget.")
    )
    func targetNeverFails() {
        target.check(sample(target.limit * 50))
    }

    @Test("A target's note says how far over it is and that nothing enforces it yet")
    func noteSaysHowFarAndThatItIsATarget() {
        let note = target.targetNote(sample(target.limit * 3))
        #expect(note.hasPrefix("BUDGET-TARGET | a target under test |"))
        #expect(note.contains("3.0×"))
        #expect(note.contains("not enforced"))
    }
}
