//
//  PerformanceBudgets.swift
//  WoodcaseTests
//

import Testing

/// The suite every performance budget lives under, and the reason they are one suite.
///
/// A timing test measures the machine as much as the code, so two of them running at
/// once measure each other. Under the default parallel run the six budgets here
/// inflated one another by about a third — `tree` of the synthetic document reported
/// 1507 ms beside its neighbours and 1115 ms alone, on the same build in the same
/// minute. ``Testing/Trait/serialized`` applies to a suite *and everything nested
/// inside it*, so declaring it once here is what makes every figure below a
/// measurement of the pipeline rather than of the scheduler.
///
/// The individual budgets are nested suites, one per file:
///
/// - ``PerformanceBudgets/TreeTests``
/// - ``PerformanceBudgets/SetTests``
/// - ``PerformanceBudgets/SetVerbTests``
/// - ``PerformanceBudgets/ShotTests``
/// - ``PerformanceBudgets/PaintedExtentWalkTests`` (a measurement, not a budget — no
///   fixed ceiling)
///
/// ```sh
/// swift test --filter Performance
/// ```
///
/// See <doc:WoodcasePerformance> for the budgets, the measured numbers, and what to
/// do when one trips.
@Suite(.serialized)
struct PerformanceBudgets {}
