//
//  PerformanceLayoutStateBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

extension PerformanceBudgets {
    /// Holds node-granular layout on a 2,000-node board to the budgets in
    /// ``LayoutStateBudget``: a hypothetical reorder and resize, a committed edit, and a
    /// committed edit inside the component every card instance draws.
    ///
    /// On the optimized build the budgets are stated for:
    ///
    /// ```sh
    /// swift run -c release WoodcaseBench budgets layout-state
    /// ```
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug board layout takes seconds."
    ))
    @MainActor
    struct LayoutStateTests {
        @Test("A hypothetical reorder in the 400-row list is within budget")
        func hypotheticalReorder() async throws {
            try await LayoutStateBudget.reorder.check(LayoutStateBudget.measureReorder())
        }

        @Test("A hypothetical resize of a list row is within budget")
        func hypotheticalResize() async throws {
            try await LayoutStateBudget.resize.check(LayoutStateBudget.measureResize())
        }

        @Test("A committed text edit updates within budget")
        func committedUpdate() throws {
            try LayoutStateBudget.update.check(LayoutStateBudget.measureUpdate())
        }

        @Test("A committed edit inside the component lays out its instances within budget")
        func committedDefinitionEdit() throws {
            try LayoutStateBudget.definition.check(LayoutStateBudget.measureDefinitionEdit())
        }
    }
}
