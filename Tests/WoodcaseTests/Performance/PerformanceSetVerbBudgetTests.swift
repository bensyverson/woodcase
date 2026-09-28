//
//  PerformanceSetVerbBudgetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

extension PerformanceBudgets {
    /// Holds `woodcase set` — the verb, as a caller runs it — to its budget.
    ///
    /// ``PerformanceBudgets/SetTests`` times the transaction under every act verb and
    /// nothing else, so it could not see what the verb adds around it: the root-overlap
    /// check before and after the edit, the write report, the outside-write note. On
    /// 2026-09-27 that check settled the whole document twice, and the binary took
    /// 401.9 ms while the transaction budget read 110.5 ms — the budgeted number and the
    /// number a caller waits for had drifted four times apart. This budget runs
    /// `SetCommand` itself, parsed from the same arguments `scripts/perf-binary` passes
    /// the binary, so everything the verb does between its arguments and its output is
    /// inside the measurement. Only process start-up and argument parsing are not, and
    /// `scripts/perf-binary`'s startup floor is that difference.
    @MainActor
    struct SetVerbTests {
        /// The promise: 200 ms for one `set` against the largest real document, the
        /// transaction's own ceiling. It held a measured ceiling of 550 ms until issue
        /// `KXKtc7`, because every artboard in `woodcase-app.pen` is an instance, so the
        /// overlap check expands nearly the whole document, and expansion round-tripped
        /// every override through JSON. Applying overrides through ``PenNodeOverlay``
        /// brought it to 172.7 ms in process (`swift test -c release --filter
        /// PerformanceBudgets`, 2026-09-27, load average 18–31) and the binary to 203.9 ms.
        private static let budget = PerformanceBudget(
            name: "set verb on woodcase-app.pen",
            release: .milliseconds(200)
        )

        @Test("The set verb, overlap warnings included, stays under budget on the largest real fixture")
        func setVerbOnLargestFixture() async throws {
            let url = try PerformanceFixture.workingCopy(of: PerformanceFixture.largestBundled())
            defer { PerformanceFixture.discard(url) }
            let rootID = try await PenFileTransaction.read(at: url) { document in
                try #require(document.rootOrder.first, "woodcase-app.pen has no root nodes.")
            }.value

            var attempt = 0
            let sample = try await PerformanceSample.measure(repetitions: Self.budget.repetitions) {
                attempt += 1
                var command = try SetCommand.parse([
                    url.path, NodeAddress.marker(forID: rootID), "common.name=Budgeted rename \(attempt)",
                ])
                try await command.run()
            }
            let written = try await PenFileTransaction.read(at: url) { document in
                document.nodes[rootID]?.common.name
            }.value
            #expect(
                written == "Budgeted rename \(attempt)",
                "Every repetition renames to a new value, so every repetition must write."
            )
            Self.budget.check(sample)
        }
    }
}
