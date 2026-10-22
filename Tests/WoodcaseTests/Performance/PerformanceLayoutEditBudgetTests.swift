//
//  PerformanceLayoutEditBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
import WoodcasePerfFixtures

extension PerformanceBudgets {
    /// Measures what one editor gesture costs the root-granular layout engine on a
    /// 2,000-node board, against the targets in ``LayoutEditBudget``.
    ///
    /// Over a target prints a `BUDGET-TARGET` line and never fails. On the optimized
    /// build the targets describe:
    ///
    /// ```sh
    /// swift run -c release WoodcaseBench budgets layout-edit
    /// ```
    ///
    /// A 2,000-node board costs seconds per gesture in a debug build, so the default
    /// `swift test` skips this suite; `WOODCASE_BUDGET_STRICT` runs it.
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug board gesture takes seconds."
    ))
    @MainActor
    struct LayoutEditTests {
        @Test("Reordering a row in the 400-row list is measured")
        func reorder() async throws {
            try await LayoutEditBudget.reorder.check(LayoutEditBudget.measureReorder())
        }

        @Test("Resizing a row in the 400-row list is measured")
        func resize() async throws {
            try await LayoutEditBudget.resize.check(LayoutEditBudget.measureResize())
        }

        @Test("Committing a text edit in the list is measured")
        func committedEdit() async throws {
            try await LayoutEditBudget.edit.check(LayoutEditBudget.measureEdit())
        }
    }
}
