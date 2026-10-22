//
//  PerformanceTreeBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

extension PerformanceBudgets {
    /// Holds the settled-tree read — what `woodcase tree` prints — to its budget.
    ///
    /// The pipeline and the ceilings are ``TreeBudget``'s, shared with
    /// `swift run -c release WoodcaseBench budgets tree`, which confirms them on the
    /// optimized build they are stated for.
    @MainActor
    struct TreeTests {
        @Test("tree of the largest real fixture stays under budget")
        func treeOfLargestFixture() async throws {
            let url = PerformanceFixture.largestReal
            let sample = try await TreeBudget.measure(TreeBudget.real, on: url)
            try Self.profileStages(of: url)
            TreeBudget.real.check(sample)
        }

        @Test("tree of a 5000-node synthetic document stays under budget")
        func treeOfSyntheticDocument() async throws {
            let url = try PerformanceFixture.syntheticFile()
            defer { PerformanceFixture.discard(url) }
            let sample = try await TreeBudget.measure(TreeBudget.synthetic, on: url)
            try Self.profileStages(of: url)
            TreeBudget.synthetic.check(sample)
        }

        /// Splits the settled read into its stages, for when a budget trips.
        ///
        /// ``TreeView/rows(of:root:depth:expandInstances:theme:properties:)`` settles the
        /// document in one call, so the only way to see *which* stage costs the
        /// milliseconds is to run the same stages side by side. This runs off
        /// ``PhaseStopwatch``, printing `PROFILE tree <stage> <ms>` lines, and does
        /// nothing at all unless `WOODCASE_TEST_PROFILE` is set — so it never lands
        /// inside a measurement it would distort.
        ///
        /// ```sh
        /// WOODCASE_TEST_PROFILE=1 swift test --filter TreeTests 2>&1 | grep PROFILE
        /// ```
        ///
        /// - Parameter url: The `.pen` file to profile.
        /// - Throws: Whatever the parser throws.
        private static func profileStages(of url: URL) throws {
            guard PhaseStopwatch.isEnabled else { return }
            var stopwatch = PhaseStopwatch("tree:\(url.lastPathComponent)")
            let data = try Data(contentsOf: url)
            stopwatch.lap("read")
            let parsed = try PenParser.parse(data)
            stopwatch.lap("parse")
            let expanded = PenRefExpander.expand(parsed)
            stopwatch.lap("expand")
            let resolved = PenVariableResolver.resolve(expanded)
            stopwatch.lap("resolve")
            let rects = PenLayoutEngine.layout(resolved)
            stopwatch.lap("layout")
            print("PROFILE tree:\(url.lastPathComponent) nodes \(rects.count)")
            stopwatch.total()
        }
    }
}
