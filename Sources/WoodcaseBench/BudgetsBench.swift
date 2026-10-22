//
//  BudgetsBench.swift
//  WoodcaseBench
//

import Foundation
import Woodcase
import WoodcasePerfFixtures

/// Runs the suite's performance budgets on an optimized build, against the release
/// ceilings they are stated for, and says which pass.
///
/// The suite runs the same bodies (`PerformanceBudgets`, `WoodcasePerfFixtures`) on the
/// default debug build, where an overage is only advisory; this is where it is confirmed
/// or dismissed, without optimizing the test target:
///
/// ```sh
/// swift run -c release WoodcaseBench budgets          # every budget
/// swift run -c release WoodcaseBench budgets tree     # the budgets whose group names `tree`
/// ```
///
/// Each budget prints its `BUDGET` line and then `PASS`, `FAIL`, or `TARGET` (over a
/// ceiling set for work not yet landed, which fails nothing). The bench exits non-zero
/// when an enforced budget fails. Read the figures beside `uptime`: a loaded machine
/// inflates even a minimum.
///
/// Two budgets stay in the suite only: `PerformanceBudgets.SetVerbTests` runs the
/// `woodcase set` command itself, which is `WoodcaseCommandCore`'s internal type, and
/// `PerformanceBudgets.ComponentLoopTests` draws its documents with the test target's
/// merge fuzzer. `scripts/perf-binary --config release` times the `set` verb end to end.
enum BudgetsBench {
    /// The bench.
    static let bench = Bench(
        name: "budgets",
        summary: "The suite's performance budgets, against their release ceilings; exits 1 if one fails",
        arguments: "[group]",
        run: { arguments in try await run(arguments) }
    )

    /// One budget the bench runs: its group, its budget, and the work that measures it.
    private struct Entry {
        /// The group `budgets <group>` selects by: tree, set, shot, layout-edit,
        /// layout-state or structural-edit.
        let group: String

        /// The ceiling.
        let budget: PerformanceBudget

        /// Measures it.
        let measure: @MainActor () async throws -> PerformanceSample
    }

    /// Why the bench exits non-zero.
    private struct Failed: Error, CustomStringConvertible {
        /// The budgets that failed.
        let names: [String]

        var description: String {
            "\(names.count) budget(s) over their release ceiling: \(names.joined(separator: "; "))"
        }
    }

    /// Every budget, in the order the suite declares them.
    @MainActor
    private static var entries: [Entry] {
        [
            Entry(group: "tree", budget: TreeBudget.real) {
                try await TreeBudget.measure(TreeBudget.real, on: PerformanceFixture.largestReal)
            },
            Entry(group: "tree", budget: TreeBudget.synthetic) {
                let url = try PerformanceFixture.syntheticFile()
                defer { PerformanceFixture.discard(url) }
                return try await TreeBudget.measure(TreeBudget.synthetic, on: url)
            },
            Entry(group: "set", budget: SetTransactionBudget.real) {
                let url = try PerformanceFixture.workingCopy(of: PerformanceFixture.largestReal)
                defer { PerformanceFixture.discard(url) }
                return try await SetTransactionBudget.measure(SetTransactionBudget.real, on: url).sample
            },
            Entry(group: "set", budget: SetTransactionBudget.synthetic) {
                let url = try PerformanceFixture.syntheticFile()
                defer { PerformanceFixture.discard(url) }
                return try await SetTransactionBudget.measure(SetTransactionBudget.synthetic, on: url).sample
            },
            Entry(group: "shot", budget: ShotBudget.real) {
                try await shot(ShotBudget.real, of: PerformanceFixture.largestReal)
            },
            Entry(group: "shot", budget: ShotBudget.synthetic) {
                let url = try PerformanceFixture.syntheticFile()
                defer { PerformanceFixture.discard(url) }
                return try await shot(ShotBudget.synthetic, of: url)
            },
            Entry(group: "layout-edit", budget: LayoutEditBudget.reorder) { try await LayoutEditBudget.measureReorder() },
            Entry(group: "layout-edit", budget: LayoutEditBudget.resize) { try await LayoutEditBudget.measureResize() },
            Entry(group: "layout-edit", budget: LayoutEditBudget.edit) { try await LayoutEditBudget.measureEdit() },
            Entry(group: "layout-state", budget: LayoutStateBudget.reorder) { try await LayoutStateBudget.measureReorder() },
            Entry(group: "layout-state", budget: LayoutStateBudget.resize) { try await LayoutStateBudget.measureResize() },
            Entry(group: "layout-state", budget: LayoutStateBudget.update) { try LayoutStateBudget.measureUpdate() },
            Entry(group: "layout-state", budget: LayoutStateBudget.definition) {
                try LayoutStateBudget.measureDefinitionEdit()
            },
            Entry(group: "structural-edit", budget: StructuralEditBudget.insert) {
                let document = EditableDocument(from: StructuralEditBudget.makeDocument())
                document.computeLayout()
                let measurement = try await StructuralEditBudget.measure(on: document)
                print(StructuralEditBudget.fullLayoutLine(measurement.fullLayout))
                return measurement.insert
            },
        ]
    }

    /// Renders the first placed artboard of `url` into a scratch PNG.
    @MainActor
    private static func shot(_ budget: PerformanceBudget, of url: URL) async throws -> PerformanceSample {
        let output = try PerformanceFixture.scratchFile(named: "shot.png")
        defer { PerformanceFixture.discard(output) }
        let node = try await ShotBudget.firstArtboardName(of: url)
        return try await ShotBudget.measure(budget, node: node, in: url, to: output)
    }

    /// Runs every budget, or those in the group `arguments` names.
    @MainActor
    private static func run(_ arguments: [String]) async throws {
        let all = entries
        let groups = Set(all.map(\.group))
        let selected: [Entry]
        switch arguments.count {
        case 0:
            selected = all
        case 1 where groups.contains(arguments[0]):
            selected = all.filter { $0.group == arguments[0] }
        default:
            throw Bench.UsageError(
                description: "usage: WoodcaseBench budgets [group]; groups: \(groups.sorted().joined(separator: ", "))"
            )
        }
        if !PerformanceBudget.isOptimized {
            print("NOTE | an unoptimized build: limits are the release ceilings × \(PerformanceBudget.debugMultiplier); "
                + "run `\(PerformanceBudget.confirmCommand)` for the figures the ceilings describe")
        }
        var failed: [String] = []
        for entry in selected {
            let sample = try await entry.measure()
            print(entry.budget.announcement(sample))
            switch entry.budget.verdict(sample) {
            case .pass:
                print("PASS | \(entry.budget.name)")
            case let .failure(report):
                print("FAIL | \(entry.budget.name)\n\(report)")
                failed.append(entry.budget.name)
            case let .advisory(note):
                print("FAIL | \(entry.budget.name)\n\(note)")
                failed.append(entry.budget.name)
            case let .target(note):
                print("TARGET | \(entry.budget.name)\n\(note)")
            }
        }
        if !failed.isEmpty { throw Failed(names: failed) }
    }
}
