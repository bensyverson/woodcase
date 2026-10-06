//
//  PerformanceComponentLoopBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

extension PerformanceBudgets {
    /// Holds a detach or an override in a document that arrives with component loops
    /// under 100 ms (leaf `xaAJeF`).
    ///
    /// The documents are the ones merge-fuzz seeds 12456 and 13964 draw with the loop
    /// guard off (``ComponentLoopFuzzTests``); before the loop rule, their detaches and
    /// overrides expanded 12 million and 80 thousand nodes. Each repetition detaches
    /// every instance and overrides one key of each, each on a fresh copy, and keeps the
    /// slowest single operation; the budget holds the fastest of those repetitions. Run:
    ///
    /// ```sh
    /// swift test -c release --filter PerformanceBudgets.ComponentLoopTests 2>&1 | grep BUDGET
    /// ```
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug run of every instance takes seconds."
    ))
    @MainActor
    struct ComponentLoopTests {
        /// The ceiling on any one detach or override, for a seed's documents.
        static func budget(seed: UInt64) -> PerformanceBudget {
            PerformanceBudget(
                name: "slowest detach or override in seed \(seed)'s loopy documents",
                release: .milliseconds(100)
            )
        }

        @Test("A detach or override in a seed's loopy documents stays under 100 ms", arguments: ComponentLoopFuzzTests.seeds)
        func detachAndOverride(seed: UInt64) throws {
            let (documents, _) = try ComponentLoopFuzzTests.loopyDocuments(seed: seed)
            #expect(!documents.isEmpty, "seed \(seed) drew no loop, so it measures nothing")
            let budget = Self.budget(seed: seed)
            let elapsed = (0 ..< budget.repetitions).map { _ in
                documents.map(ComponentLoopFuzzTests.slowestDetachAndOverride).max() ?? .zero
            }
            budget.check(PerformanceSample(elapsed: elapsed))
        }
    }
}
