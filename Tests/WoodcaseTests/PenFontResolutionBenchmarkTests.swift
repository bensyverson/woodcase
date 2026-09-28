//
//  PenFontResolutionBenchmarkTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Throughput benchmarks for ``PenTextMeasurer/resolveFont(family:size:weight:style:)``.
///
/// `PenLayoutBenchmarkTests` measures the layout engine with a no-op text
/// measurer, so it is blind to font resolution cost. These benchmarks are the
/// instrument for the memoization added in `b2a13c7`: they separate the case
/// that is memoized (an available family) from the case that is not (a family
/// that is absent, and so resolves to the fallback).
///
/// Reproduce with:
/// `swift test --filter "PenFontResolutionBenchmarkTests"`
struct PenFontResolutionBenchmarkTests {
    /// A family that is guaranteed absent, so every resolution falls back.
    private let absentFamily = "Woodcase Absent Benchmark Family"

    /// A family present on every supported platform.
    private let presentFamily = "Helvetica"

    /// Runs a benchmark: 1 warmup pass, 10 measured iterations, returns the median in seconds.
    private func benchmark(_ label: String, body: () -> Void) -> Double {
        body()

        let clock = ContinuousClock()
        var durations: [Double] = []
        for _ in 0 ..< 10 {
            let elapsed = clock.measure { body() }
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            durations.append(seconds)
        }
        durations.sort()
        let median = durations[durations.count / 2]
        print("[\(label)] median: \(String(format: "%.3f", median * 1000))ms")
        return median
    }

    @Test("Resolve 10000 fonts from a present family")
    func resolvePresentFamily() {
        _ = benchmark("resolve-present-10000") {
            for _ in 0 ..< 10000 {
                _ = PenTextMeasurer.resolveFont(
                    family: presentFamily, size: 16, weight: "normal", style: "normal"
                )
            }
        }
    }

    @Test("Resolve 10000 fonts from an absent family")
    func resolveAbsentFamily() {
        _ = benchmark("resolve-absent-10000") {
            for _ in 0 ..< 10000 {
                _ = PenTextMeasurer.resolveFont(
                    family: absentFamily, size: 16, weight: "normal", style: "normal"
                )
            }
        }
    }

    @Test("Measure 2000 strings across a present and an absent family")
    func measureMixedFamilies() {
        _ = benchmark("measure-mixed-2000") {
            for i in 0 ..< 2000 {
                let family = i % 2 == 0 ? presentFamily : absentFamily
                _ = PenTextMeasurer.measure(
                    "The quick brown fox",
                    fontFamily: family,
                    fontSize: 16,
                    fontWeight: "normal"
                )
            }
        }
    }
}
