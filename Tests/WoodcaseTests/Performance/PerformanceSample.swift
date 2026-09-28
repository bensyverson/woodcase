//
//  PerformanceSample.swift
//  WoodcaseTests
//

import Foundation
import Woodcase

/// The elapsed times of several in-process repetitions of one pipeline.
///
/// A budget is asserted on ``best`` and never on a single run. The machine these
/// tests run on is routinely shared with other builds, and a single sample there can
/// be four times the true figure while the minimum barely moves — so the minimum is
/// the measurement, and the spread between it and the rest is how loaded the machine
/// was.
///
/// The work is timed **in process**. Timing the `woodcase` binary instead would put
/// process start-up and an unoptimized `ArgumentParser` into every number, neither of
/// which is the library's to fix; the binary's end-to-end time is recorded separately
/// in <doc:WoodcasePerformance> as information.
struct PerformanceSample: Friendly {
    /// Every repetition's elapsed time, in the order they ran.
    var elapsed: [Duration]

    /// The fastest repetition — the only figure a budget is checked against.
    ///
    /// An empty sample reports zero, which cannot happen: ``measure(repetitions:_:)``
    /// refuses to run fewer than one repetition.
    var best: Duration {
        elapsed.min() ?? .zero
    }

    /// Every repetition, fastest first, for a failure message.
    var summary: String {
        elapsed
            .sorted()
            .map(PerformanceBudget.milliseconds)
            .joined(separator: ", ")
    }

    /// Runs `body` repeatedly and keeps how long each run took.
    ///
    /// The first repetition warms whatever the pipeline caches — font resolution,
    /// CoreText's own state, the file system's page cache — which is exactly why the
    /// budgets are stated warm and why the minimum, not the mean, is the answer.
    ///
    /// - Parameters:
    ///   - repetitions: How many times to run `body`. At least one; a smaller number
    ///     is raised to one rather than producing an empty sample.
    ///   - body: The pipeline to time. Run on the main actor, one repetition at a
    ///     time, so nothing in this suite overlaps with itself.
    /// - Returns: The elapsed time of every repetition.
    /// - Throws: Anything `body` throws, on the repetition that threw.
    @MainActor
    static func measure(
        repetitions: Int,
        _ body: () async throws -> Void
    ) async rethrows -> PerformanceSample {
        var elapsed: [Duration] = []
        for _ in 0 ..< max(1, repetitions) {
            let clock = ContinuousClock.now
            try await body()
            elapsed.append(clock.duration(to: ContinuousClock.now))
        }
        return PerformanceSample(elapsed: elapsed)
    }
}
