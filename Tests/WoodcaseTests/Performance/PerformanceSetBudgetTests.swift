//
//  PerformanceSetBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

extension PerformanceBudgets {
    /// Holds one write transaction — open, apply, write — to its budget.
    ///
    /// This is the round trip behind every act verb, not just `set`: ``PenFileTransaction``
    /// takes the exclusive lock, parses the file, applies the operation through
    /// ``BatchApplier``, encodes the result, compares it against what it parsed, renames
    /// the new bytes over the old, and appends the activity event. An agent editing a
    /// document does this once per change, so its cost is the cost of thinking out loud.
    ///
    /// Every repetition sets a *different* name, so every repetition genuinely writes:
    /// a transaction whose document encodes to the same bytes returns without writing at
    /// all, and timing that would be timing half the pipeline.
    @MainActor
    struct SetTests {
        /// 200 ms for one write against the largest real document — the leaf's number.
        private static let budget = PerformanceBudget(
            name: "set transaction on woodcase-app.pen",
            release: .milliseconds(200)
        )

        /// 1300 ms against a document an order of magnitude larger.
        ///
        /// A write is dominated by the two things that scale with the file rather than
        /// with the edit — parsing 5000 nodes in and encoding 5000 nodes back out — so
        /// the leaf's 200 ms is not a promise anyone made about a document this size.
        /// This is a *measured* ceiling, and until 2026-08-30 it was measured wrong: it
        /// read 800 ms, from a debug figure divided by ``PerformanceBudget/debugMultiplier``
        /// because `swift test -c release` could not run. That division does not hold
        /// here — this pipeline's real optimizer ratio is 1244.8 ÷ 1023.9 = **1.22×**,
        /// not 2.5×, because almost all of it is `JSONDecoder` and `JSONEncoder`. The
        /// first optimized run measured 1023.9 ms
        /// (`swift test -c release --filter Performance`, minimum of 5, load average 3.6,
        /// samples spread 0.3 %); 1300 ms keeps the 1.27× headroom the synthetic `tree`
        /// ceiling carries. Nothing got slower — the number had never been measured.
        private static let syntheticBudget = PerformanceBudget(
            name: "set transaction on a synthetic \(PerformanceFixture.syntheticNodeCount)-node document",
            release: .milliseconds(1300)
        )

        @Test("A set transaction on the largest real fixture stays under budget")
        func setOnLargestFixture() async throws {
            let url = try PerformanceFixture.workingCopy(of: PerformanceFixture.largestBundled())
            defer { PerformanceFixture.discard(url) }
            try await Self.check(Self.budget, on: url)
        }

        @Test("A set transaction on a 5000-node synthetic document stays under budget")
        func setOnSyntheticDocument() async throws {
            let url = try PerformanceFixture.syntheticFile()
            defer { PerformanceFixture.discard(url) }
            try await Self.check(Self.syntheticBudget, on: url)
        }

        // MARK: - The pipeline

        /// Measures `budget.repetitions` writes against `url` and asserts the minimum.
        ///
        /// - Parameters:
        ///   - budget: The ceiling to hold the minimum to.
        ///   - url: A **writable** copy of a `.pen` file; every repetition rewrites it.
        /// - Throws: Whatever the transaction throws, or an expectation failure when the
        ///   file has no addressable root node.
        private static func check(_ budget: PerformanceBudget, on url: URL) async throws {
            let rootID = try await firstRootID(of: url)
            let address = try #require(
                NodeAddress(NodeAddress.marker(forID: rootID)),
                "A node id is always a valid one-segment address."
            )
            let log = ActivityLog(home: url.deletingLastPathComponent())

            var attempt = 0
            var writes = 0
            let sample = try await PerformanceSample.measure(repetitions: budget.repetitions) {
                attempt += 1
                if try await set(name: "Budgeted rename \(attempt)", on: address, in: url, log: log) {
                    writes += 1
                }
            }
            #expect(
                writes == budget.repetitions,
                "Every repetition renames to a new value, so every repetition must write."
            )
            budget.check(sample)
        }

        /// Everything `woodcase set <file> <node> common.name=… --as ana` does.
        ///
        /// - Parameters:
        ///   - name: The new name — different every repetition, so the write really happens.
        ///   - address: The node to patch.
        ///   - url: The `.pen` file to edit.
        ///   - log: Where the attributed event goes; a file beside the document, so the
        ///     measurement includes the append the CLI pays for and no test writes into
        ///     the developer's real `$WOODCASE_HOME`.
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

        /// The id of the document's first root node, so no test hard-codes a fixture id.
        ///
        /// - Parameter url: The `.pen` file to read.
        /// - Returns: The first id in ``EditableDocument/rootOrder``.
        /// - Throws: An expectation failure for a document with no root nodes.
        private static func firstRootID(of url: URL) async throws -> String {
            try await PenFileTransaction.read(at: url) { document in
                try #require(document.rootOrder.first, "\(url.lastPathComponent) has no root nodes.")
            }.value
        }
    }
}
