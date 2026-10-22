//
//  BenchClock.swift
//  WoodcaseBench
//

import Foundation

/// Times a piece of work several times and prints a `PROBE` line: the median and the
/// p90, in milliseconds.
///
/// The median and not the minimum: a bench is a record of what a call costs, read beside
/// `uptime`, not a budget that must survive a loaded machine (the suite's budgets take
/// the minimum for that).
enum BenchClock {
    /// Milliseconds in a duration.
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Runs `body` `runs` times and prints `PROBE <label> median <m> ms p90 <p> ms`.
    ///
    /// - Parameters:
    ///   - label: What was timed.
    ///   - runs: How many times to run `body`; at least one.
    ///   - body: The work.
    /// - Returns: Every run's time, fastest first.
    @discardableResult
    static func measure(_ label: String, runs: Int, _ body: () throws -> Void) rethrows -> [Duration] {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< max(1, runs) {
            try samples.append(clock.measure(body))
        }
        samples.sort()
        print(String(
            format: "PROBE %@ median %.4f ms p90 %.4f ms",
            label, milliseconds(samples[samples.count / 2]), milliseconds(samples[samples.count * 9 / 10])
        ))
        return samples
    }
}
