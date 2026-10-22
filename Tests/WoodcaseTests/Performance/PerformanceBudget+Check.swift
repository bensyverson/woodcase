//
//  PerformanceBudget+Check.swift
//  WoodcaseTests
//

import Testing
import WoodcasePerfFixtures

extension PerformanceBudget {
    /// Announces a measurement and records a failure if it is one.
    ///
    /// The one call site a budget test needs: it prints the `BUDGET` line either way and
    /// acts on ``PerformanceBudget/verdict(_:)`` — a failure is an `Issue`, a note is
    /// printed. `swift run -c release WoodcaseBench budgets` makes the same decision on
    /// the optimized build. See <doc:WoodcasePerformance>.
    ///
    /// - Parameters:
    ///   - sample: The repetitions that were measured.
    ///   - sourceLocation: Where to attribute a failure; defaults to the caller.
    func check(_ sample: PerformanceSample, sourceLocation: SourceLocation = #_sourceLocation) {
        print(announcement(sample))
        switch verdict(sample) {
        case .pass:
            break
        case let .failure(report):
            Issue.record(Comment(rawValue: report), sourceLocation: sourceLocation)
        case let .advisory(note), let .target(note):
            print(note)
        }
    }
}
