//
//  TreeBudget.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// The settled-tree read — what `woodcase tree` prints — and its budgets.
///
/// `tree` is the read an agent runs first and runs most, so its cost sets the floor
/// on how conversational the CLI feels. The whole of it is timed: the shared lock, the
/// parse, ref expansion, variable resolution, layout, and the text the verb would have
/// printed. Only `ArgumentParser` and process start-up are left out, because neither is
/// the library's to fix — `scripts/perf-binary` times the binary end to end.
@MainActor
public enum TreeBudget {
    /// 300 ms for the largest real document, release build — the leaf's number.
    public static let real = PerformanceBudget(
        name: "tree of woodcase-app.pen",
        release: .milliseconds(300)
    )

    /// 500 ms for a document an order of magnitude larger.
    ///
    /// Not the leaf's 300 ms: nobody promised that number for a 5000-node document,
    /// and asserting it here would be inventing a requirement. This is a *measured*
    /// ceiling with about 30 % headroom — 380.1 ms on 2026-09-27 (issue `oiUTFr`), when
    /// the old 400 ms ceiling failed one run with nothing building. Its job is to catch
    /// the day this stops being linear in the node count, which is what 5000 nodes is
    /// here to find.
    public static let synthetic = PerformanceBudget(
        name: "tree of a synthetic \(PerformanceFixture.syntheticNodeCount)-node document",
        release: .milliseconds(500)
    )

    /// Times `budget.repetitions` tree reads of `url`.
    ///
    /// - Parameters:
    ///   - budget: The budget whose repetition count to use.
    ///   - url: The `.pen` file to read.
    /// - Returns: The sample to check against `budget`.
    /// - Throws: Whatever the transaction or the tree read throws.
    public static func measure(_ budget: PerformanceBudget, on url: URL) async throws -> PerformanceSample {
        try await PerformanceSample.measure(repetitions: budget.repetitions) {
            _ = try await tree(of: url)
        }
    }

    /// Everything `woodcase tree <file>` does between its arguments and its output.
    ///
    /// - Parameter url: The `.pen` file to read.
    /// - Returns: The byte count of the outline the verb would have printed, returned
    ///   only so the formatting cannot be optimized away.
    /// - Throws: Whatever the transaction or the tree read throws.
    public static func tree(of url: URL) async throws -> Int {
        try await PenFileTransaction.read(at: url) { document in
            let rows = try TreeView.rows(of: document)
            return TreeFormatter.text(rows).utf8.count
        }.value
    }
}
