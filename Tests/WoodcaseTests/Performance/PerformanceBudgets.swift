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
/// 1507 ms beside its neighbors and 1115 ms alone, on the same build in the same
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
/// - ``PerformanceBudgets/LayoutEditTests`` (targets, not yet enforced; runs only on a
///   strict build)
/// - ``PerformanceBudgets/ComponentLoopTests`` (runs only on a strict build)
///
/// The budgets and the pipelines they time live in `WoodcasePerfFixtures`, so the
/// suite runs them on the debug build (where an overage is advisory) and
/// `swift run -c release WoodcaseBench budgets` confirms them on the optimized build
/// their ceilings are stated for. Measurements with no ceiling — what a call costs on
/// an optimized build — are not here either: they are `WoodcaseBench` benches
/// (`swift run -c release WoodcaseBench list`).
///
/// ```sh
/// swift test --filter Performance
/// swift run -c release WoodcaseBench budgets
/// ```
///
/// See <doc:WoodcasePerformance> for the budgets, the measured numbers, and what to
/// do when one trips.
@Suite(.serialized)
struct PerformanceBudgets {}
