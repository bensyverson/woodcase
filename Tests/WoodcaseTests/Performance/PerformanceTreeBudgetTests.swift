//
//  PerformanceTreeBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

extension PerformanceBudgets {
    /// Holds the settled-tree read — what `woodcase tree` prints — to its budget.
    ///
    /// `tree` is the read an agent runs first and runs most, so its cost sets the floor
    /// on how conversational the CLI feels. The whole of it is timed: the shared lock,
    /// the parse, ref expansion, variable resolution, layout, and the text the verb would
    /// have printed. Only ``ArgumentParser`` and process start-up are left out, because
    /// neither is the library's to fix — see <doc:WoodcasePerformance> for the binary's
    /// end-to-end time.
    @MainActor
    struct TreeTests {
        /// 300 ms for the largest real document, release build — the leaf's number.
        private static let budget = PerformanceBudget(
            name: "tree of woodcase-app.pen",
            release: .milliseconds(300)
        )

        /// 500 ms for a document an order of magnitude larger.
        ///
        /// Not the leaf's 300 ms: nobody promised that number for a 5000-node document,
        /// and asserting it here would be inventing a requirement. This is a *measured*
        /// ceiling with about 30 % headroom — 380.1 ms on 2026-09-27 (issue `oiUTFr`),
        /// when the old 400 ms ceiling failed one run with nothing building. Its job is
        /// to catch the day this stops being linear in the node count, which is what
        /// 5000 nodes is here to find.
        private static let syntheticBudget = PerformanceBudget(
            name: "tree of a synthetic \(PerformanceFixture.syntheticNodeCount)-node document",
            release: .milliseconds(500)
        )

        @Test("tree of the largest real fixture stays under budget")
        func treeOfLargestFixture() async throws {
            let url = try PerformanceFixture.largestBundled()
            let budget = Self.budget
            let sample = try await PerformanceSample.measure(repetitions: budget.repetitions) {
                _ = try await Self.tree(of: url)
            }
            try Self.profileStages(of: url)
            budget.check(sample)
        }

        @Test("tree of a 5000-node synthetic document stays under budget")
        func treeOfSyntheticDocument() async throws {
            let url = try PerformanceFixture.syntheticFile()
            defer { PerformanceFixture.discard(url) }
            let budget = Self.syntheticBudget
            let sample = try await PerformanceSample.measure(repetitions: budget.repetitions) {
                _ = try await Self.tree(of: url)
            }
            try Self.profileStages(of: url)
            budget.check(sample)
        }

        // MARK: - The pipeline

        /// Everything `woodcase tree <file>` does between its arguments and its output.
        ///
        /// - Parameter url: The `.pen` file to read.
        /// - Returns: The byte count of the outline the verb would have printed, returned
        ///   only so the formatting cannot be optimized away.
        /// - Throws: Whatever the transaction or the tree read throws.
        private static func tree(of url: URL) async throws -> Int {
            try await PenFileTransaction.read(at: url) { document in
                let rows = try TreeView.rows(of: document)
                return TreeFormatter.text(rows).utf8.count
            }.value
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
