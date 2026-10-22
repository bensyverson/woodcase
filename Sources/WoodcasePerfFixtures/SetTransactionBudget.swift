//
//  SetTransactionBudget.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// One write transaction — open, apply, write — and its budgets.
///
/// This is the round trip behind every act verb, not just `set`: ``PenFileTransaction``
/// takes the exclusive lock, parses the file, applies the operation through
/// ``BatchApplier``, encodes the result, compares it against what it parsed, renames the
/// new bytes over the old, and appends the activity event. An agent editing a document
/// does this once per change, so its cost is the cost of thinking out loud.
///
/// Every repetition sets a *different* name, so every repetition genuinely writes: a
/// transaction whose document encodes to the same bytes returns without writing at all,
/// and timing that would be timing half the pipeline.
@MainActor
public enum SetTransactionBudget {
    /// 200 ms for one write against the largest real document — the leaf's number.
    public static let real = PerformanceBudget(
        name: "set transaction on woodcase-app.pen",
        release: .milliseconds(200)
    )

    /// 1300 ms against a document an order of magnitude larger.
    ///
    /// A write is dominated by the two things that scale with the file rather than with
    /// the edit — parsing 5000 nodes in and encoding 5000 nodes back out — so the leaf's
    /// 200 ms is not a promise anyone made about a document this size. This is a
    /// *measured* ceiling, and until 2026-08-30 it was measured wrong: it read 800 ms,
    /// from a debug figure divided by ``PerformanceBudget/debugMultiplier`` because no
    /// optimized run of the budgets worked yet. That division does not hold here — this
    /// pipeline's real optimizer ratio is 1244.8 ÷ 1023.9 = **1.22×**, not 2.5×, because
    /// almost all of it is `JSONDecoder` and `JSONEncoder`. The first optimized run
    /// measured 1023.9 ms (minimum of 5, load average 3.6, samples spread 0.3 %); 1300 ms
    /// keeps the 1.27× headroom the synthetic `tree` ceiling carries. Nothing got
    /// slower — the number had never been measured.
    public static let synthetic = PerformanceBudget(
        name: "set transaction on a synthetic \(PerformanceFixture.syntheticNodeCount)-node document",
        release: .milliseconds(1300)
    )

    /// What one measurement found.
    public struct Measurement: Friendly {
        /// The repetitions' times.
        public var sample: PerformanceSample

        /// How many repetitions rewrote the file; every one should.
        public var writes: Int
    }

    /// Times `budget.repetitions` writes against `url`.
    ///
    /// - Parameters:
    ///   - budget: The budget whose repetition count to use.
    ///   - url: A **writable** copy of a `.pen` file; every repetition rewrites it.
    /// - Returns: The sample, and how many repetitions wrote.
    /// - Throws: Whatever the transaction throws, or a ``PerformanceFixture/SetupError``
    ///   when the file has no root node.
    public static func measure(_ budget: PerformanceBudget, on url: URL) async throws -> Measurement {
        let rootID = try await firstRootID(of: url)
        guard let address = NodeAddress(NodeAddress.marker(forID: rootID)) else {
            throw PerformanceFixture.SetupError("\(rootID) is not a valid one-segment address.")
        }
        let log = ActivityLog(home: url.deletingLastPathComponent())

        var attempt = 0
        var writes = 0
        let sample = try await PerformanceSample.measure(repetitions: budget.repetitions) {
            attempt += 1
            if try await set(name: "Budgeted rename \(attempt)", on: address, in: url, log: log) {
                writes += 1
            }
        }
        return Measurement(sample: sample, writes: writes)
    }

    /// Everything `woodcase set <file> <node> common.name=… --as ana` does.
    ///
    /// - Parameters:
    ///   - name: The new name — different every repetition, so the write really happens.
    ///   - address: The node to patch.
    ///   - url: The `.pen` file to edit.
    ///   - log: Where the attributed event goes; a file beside the document, so the
    ///     measurement includes the append the CLI pays for and nothing writes into the
    ///     developer's real `$WOODCASE_HOME`.
    /// - Returns: Whether the file was rewritten.
    /// - Throws: Whatever the transaction or the applier throws.
    private static func set(
        name: String,
        on address: NodeAddress,
        in url: URL,
        log: ActivityLog
    ) async throws -> Bool {
        try await PenFileTransaction.run(at: url, identity: "budgeter", log: log) { document, recorder in
            _ = try BatchApplier.applyOne(
                .set(BatchOperation.SetOp(target: address, props: ["common.name": .string(name)])),
                to: document,
                recorder: recorder
            )
        }.didWrite
    }

    /// The id of the document's first root node, so nothing hard-codes a fixture id.
    ///
    /// - Parameter url: The `.pen` file to read.
    /// - Returns: The first id in ``EditableDocument/rootOrder``.
    /// - Throws: A ``PerformanceFixture/SetupError`` for a document with no root nodes.
    public static func firstRootID(of url: URL) async throws -> String {
        try await PenFileTransaction.read(at: url) { document in
            guard let first = document.rootOrder.first else {
                throw PerformanceFixture.SetupError("\(url.lastPathComponent) has no root nodes.")
            }
            return first
        }.value
    }
}
