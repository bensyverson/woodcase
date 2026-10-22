//
//  PerformanceStructuralEditBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase
import WoodcasePerfFixtures

extension PerformanceBudgets {
    /// Measures a one-node insert on a 2,500-node document of eight boards (Penumbra
    /// ruling R20) against ``StructuralEditBudget``'s target, and checks the insert
    /// dirtied only its own board.
    ///
    /// On the optimized build the target describes:
    ///
    /// ```sh
    /// swift run -c release WoodcaseBench budgets structural-edit
    /// ```
    @Suite(.enabled(
        if: PerformanceBudget.isStrict,
        "Needs a release build or WOODCASE_BUDGET_STRICT: a debug 2,500-node layout takes seconds."
    ))
    @MainActor
    struct StructuralEditTests {
        @Test("A one-node insert lays out one board of eight")
        func insert() async throws {
            let document = EditableDocument(from: StructuralEditBudget.makeDocument())
            document.computeLayout()
            #expect(StructuralEditBudget.count(document.materialize().children) == StructuralEditBudget.nodeCount)

            let measurement = try await StructuralEditBudget.measure(on: document)
            print(StructuralEditBudget.fullLayoutLine(measurement.fullLayout))
            #expect(document.dirtyLayoutNodeIDs.isSuperset(of: [
                StructuralEditBudget.insertListID, StructuralEditBudget.insertBoardID,
            ]))
            StructuralEditBudget.insert.check(measurement.insert)
        }
    }
}
