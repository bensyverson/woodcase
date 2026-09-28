//
//  PageHost+Deadline.swift
//  WoodcaseViewerTests
//

#if os(macOS)

    import Foundation
    import SleepyHollow
    import Testing

    /// The only doors a browser test uses into its page: `PageHost`'s load and evaluate,
    /// each failing its test by name when the page does not answer.
    ///
    /// The deadline itself is SleepyHollow's: every call into a page waits at most the
    /// host's `callBudget` (60 s by default) and then throws `SleepyError` of kind
    /// `.timeout` naming the call, and a load's navigation is bounded by its own budget.
    /// What these doors add is the *name*: every bench's `ask` swallows errors with
    /// `try?`, so a thrown timeout alone would surface only as a later expectation
    /// failing for no stated reason. Here a timeout is recorded as an issue first.
    /// `PageDeadlineTests` keeps every browser test on these doors.
    extension PageHost {
        /// Runs `body` in `world` like `evaluate(_:in:budget:)`, recording a timeout as
        /// an issue naming the call.
        ///
        /// - Parameters:
        ///   - body: An async JavaScript function body that returns the value to
        ///     transport.
        ///   - world: The content world to run it in.
        ///   - budget: How long to wait for the answer, or `nil` for the host's
        ///     `callBudget`.
        /// - Returns: The body's value as JSON text.
        /// - Throws: Whatever `evaluate` throws; a `.timeout` is recorded first.
        @discardableResult
        func boundedEvaluate(
            _ body: String,
            in world: InjectedScript.World = .isolated,
            within budget: TimeInterval? = nil
        ) async throws -> String {
            try await Self.recordingTimeout {
                try await self.evaluate(body, in: world, budget: budget)
            }
        }

        /// Loads `url` like `load(_:)`, recording a timeout — of the navigation or of
        /// the console count a load ends with — as an issue naming the load.
        ///
        /// - Parameter url: The page to load.
        /// - Returns: The facts `load` reports.
        /// - Throws: Whatever `load` throws; a `.timeout` is recorded first.
        @discardableResult
        func boundedLoad(_ url: URL) async throws -> PageFacts {
            try await Self.recordingTimeout {
                try await self.load(url)
            }
        }

        /// Runs `work` and records a `SleepyError` of kind `.timeout` as an issue before
        /// rethrowing it.
        private static func recordingTimeout<T>(_ work: () async throws -> T) async throws -> T {
            do {
                return try await work()
            } catch let error as SleepyError where error.kind == .timeout {
                Issue.record(error)
                throw error
            }
        }
    }

#endif
