//
//  PerformanceSetBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

extension PerformanceBudgets {
    /// Holds one write transaction — open, apply, write — to its budget.
    ///
    /// The pipeline and the ceilings are ``SetTransactionBudget``'s, shared with
    /// `swift run -c release WoodcaseBench budgets set`, which confirms them on the
    /// optimized build they are stated for.
    @MainActor
    struct SetTests {
        @Test("A set transaction on the largest real fixture stays under budget")
        func setOnLargestFixture() async throws {
            let url = try PerformanceFixture.workingCopy(of: PerformanceFixture.largestReal)
            defer { PerformanceFixture.discard(url) }
            try await Self.check(SetTransactionBudget.real, on: url)
        }

        @Test("A set transaction on a 5000-node synthetic document stays under budget")
        func setOnSyntheticDocument() async throws {
            let url = try PerformanceFixture.syntheticFile()
            defer { PerformanceFixture.discard(url) }
            try await Self.check(SetTransactionBudget.synthetic, on: url)
        }

        /// Measures `budget.repetitions` writes against `url` and asserts the minimum.
        ///
        /// - Parameters:
        ///   - budget: The ceiling to hold the minimum to.
        ///   - url: A **writable** copy of a `.pen` file; every repetition rewrites it.
        /// - Throws: Whatever the transaction throws.
        private static func check(_ budget: PerformanceBudget, on url: URL) async throws {
            let measurement = try await SetTransactionBudget.measure(budget, on: url)
            #expect(
                measurement.writes == budget.repetitions,
                "Every repetition renames to a new value, so every repetition must write."
            )
            budget.check(measurement.sample)
        }
    }
}
