//
//  PerformanceShotBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

extension PerformanceBudgets {
    /// Holds the render of one artboard — what `woodcase shot` writes — to its budget.
    ///
    /// The pipeline and the ceilings are ``ShotBudget``'s, shared with
    /// `swift run -c release WoodcaseBench budgets shot`, which confirms them on the
    /// optimized build they are stated for.
    @MainActor
    struct ShotTests {
        @Test("A shot of one artboard of the largest real fixture stays under budget")
        func shotOfLargestFixture() async throws {
            let url = PerformanceFixture.largestReal
            let output = try PerformanceFixture.scratchFile(named: "shot.png")
            defer { PerformanceFixture.discard(output) }
            let node = try await ShotBudget.firstArtboardName(of: url)
            try await Self.check(ShotBudget.real, node: node, in: url, to: output)
        }

        @Test("A shot of one artboard of a 5000-node synthetic document stays under budget")
        func shotOfSyntheticDocument() async throws {
            let url = try PerformanceFixture.syntheticFile()
            defer { PerformanceFixture.discard(url) }
            let output = url.deletingLastPathComponent().appendingPathComponent("shot.png")
            let node = try await ShotBudget.firstArtboardName(of: url)
            #expect(node == SyntheticPenDocument.firstArtboardName)
            try await Self.check(ShotBudget.synthetic, node: node, in: url, to: output)
        }

        /// Measures `budget.repetitions` renders and asserts the minimum.
        private static func check(
            _ budget: PerformanceBudget,
            node: String,
            in url: URL,
            to output: URL
        ) async throws {
            let sample = try await ShotBudget.measure(budget, node: node, in: url, to: output)
            #expect(FileManager.default.fileExists(atPath: output.path), "The render wrote no PNG.")
            budget.check(sample)
        }
    }
}
