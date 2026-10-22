//
//  PerformanceBudget.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// A ceiling one pipeline must stay under, and what that ceiling becomes in a build
/// without the optimizer.
///
/// The budgets are stated for a **release** build, because that is what anybody
/// consuming Woodcase actually runs. The bench confirms them there, verbatim:
///
/// ```sh
/// swift run -c release WoodcaseBench budgets
/// ```
///
/// The suite runs the same bodies on the default unoptimized `swift test`, where every
/// figure is several times larger — the layout engine, the ref expander and the parser
/// spend their time in generic `Array`/`Dictionary` subscripts, enum copies and
/// retain/release traffic that only `-O` removes. Rather than carry two unrelated sets
/// of numbers, the same budget is scaled by ``debugMultiplier``. Never confirm a budget
/// with `swift test -c release`: it optimizes every file of the test target to run one
/// probe (`project/2026-10-21-build-test-loop-baseline.md`).
///
/// Nothing here is asserted against a single wall-clock sample: a budget is always
/// checked against ``PerformanceSample/best``, the minimum of several in-process
/// repetitions. A loaded machine inflates a single run several-fold (see
/// `project/2026-08-29-test-suite-speed.md`), and the minimum is the figure that survives
/// a neighbor building in another worktree.
public struct PerformanceBudget: Friendly {
    /// How much slower the same pipeline is when built without optimization.
    ///
    /// Measured on both sides by the budgets themselves — `swift test --filter Performance`
    /// (load 13, 2026-08-29) against the optimized test build that confirmed budgets then
    /// (load 3.6, 2026-08-30), minimum of 5 each:
    ///
    /// | pipeline | debug | release | ratio |
    /// | --- | --- | --- | --- |
    /// | `tree` `woodcase-app.pen` | 410.5 ms | 230.8 ms | 1.78× |
    /// | `tree` synthetic 5000 | 593.0 ms | 324.2 ms | 1.83× |
    /// | `set` `woodcase-app.pen` | 143.2 ms | 120.6 ms | 1.19× |
    /// | `set` synthetic 5000 | 1244.8 ms | 1023.9 ms | 1.22× |
    /// | `shot` `woodcase-app.pen` | 369.4 ms | 235.7 ms | 1.57× |
    /// | `shot` synthetic 5000 | 569.3 ms | 317.4 ms | 1.79× |
    ///
    /// The worst case is **1.83×**, and load inflates the debug column, so the real
    /// ratios are no larger. The constant rounds that up to leave room for scheduler
    /// noise on the debug side, and no further: a generous multiplier would let the
    /// unoptimized run pass a budget the optimized run fails, which is the one thing
    /// this constant must not do.
    ///
    /// Scaling one number *by* this constant is what it must never be used for. The
    /// spread above is 1.19× to 1.83×; a synthetic `set` ceiling derived that way sat
    /// 500 ms under the truth until an optimized run could finally measure it.
    ///
    /// The ratios are small because most of the time is not in our Swift at all — it
    /// is in CoreText measuring strings and in `JSONEncoder`, both already optimized
    /// inside the system frameworks. See `WoodcasePerformance.md`.
    public static let debugMultiplier: Double = 2.5

    /// Whether this build asserts ``release`` verbatim.
    ///
    /// `false` under the default `swift test`, which builds unoptimized; `true` under
    /// `swift run -c release WoodcaseBench budgets`.
    public static let isOptimized: Bool = {
        #if DEBUG
            false
        #else
            true
        #endif
    }()

    /// The command that confirms a budget on the build it is stated for.
    public static let confirmCommand = "swift run -c release WoodcaseBench budgets"

    /// What is being budgeted, as it appears in a failure — `"tree of woodcase-app.pen"`.
    public var name: String

    /// The ceiling on a release build.
    public var release: Duration

    /// How many in-process repetitions a measurement takes the minimum of.
    ///
    /// Five is enough for the minimum to shake off a scheduler hiccup and cheap enough
    /// that the whole performance suite stays a rounding error on the full run.
    public var repetitions: Int = 5

    /// Whether being over the ceiling can fail a run.
    public var standing: Standing = .enforced

    /// Creates a budget.
    ///
    /// - Parameters:
    ///   - name: What is being budgeted, as a failure names it.
    ///   - release: The ceiling on a release build.
    ///   - repetitions: How many repetitions a measurement takes the minimum of.
    ///   - standing: Whether being over the ceiling can fail a run.
    public init(name: String, release: Duration, repetitions: Int = 5, standing: Standing = .enforced) {
        self.name = name
        self.release = release
        self.repetitions = repetitions
        self.standing = standing
    }

    /// Whether a budget is a promise about code that exists or a target for code that
    /// does not exist yet.
    public enum Standing: Friendly {
        /// A ceiling the code is held to: ``verdict(_:)`` is a failure on a strict run
        /// that is over it.
        case enforced

        /// A ceiling a design set for work that has not landed. Over it prints a
        /// ``targetNote(_:)`` on every build and never fails; the leaf that meets the
        /// target changes the budget to ``enforced``.
        case target
    }

    /// What being over or under the limit means for one measurement.
    public enum Verdict: Friendly {
        /// At or under ``limit``.
        case pass

        /// Over an ``Standing/enforced`` budget on a strict build: the run fails, with
        /// this ``report(_:)``.
        case failure(String)

        /// Over an ``Standing/enforced`` budget on an advisory build: a warning, with
        /// this ``advisory(_:)`` line.
        case advisory(String)

        /// Over a ``Standing/target`` budget, on any build: a note, with this
        /// ``targetNote(_:)`` line.
        case target(String)
    }

    /// The ceiling this build is held to: ``release``, scaled by ``debugMultiplier``
    /// when the build is unoptimized.
    public var limit: Duration {
        Self.isOptimized ? release : release * Self.debugMultiplier
    }

    /// Whether a measurement is inside the budget.
    ///
    /// - Parameter measured: The figure to check — always a minimum, never one sample.
    /// - Returns: `true` when `measured` is at or under ``limit``.
    public func admits(_ measured: Duration) -> Bool {
        measured <= limit
    }

    /// The environment variable that makes a debug run assert its budgets verbatim.
    public static let strictEnvironmentVariable = "WOODCASE_BUDGET_STRICT"

    /// Whether a measurement over ``limit`` fails the run.
    ///
    /// True on an optimized build, which is the build the budgets are stated for, and
    /// on any build where `WOODCASE_BUDGET_STRICT` is set. False under the default
    /// `swift test`, where the number measured is not the number the budget describes:
    /// ``debugMultiplier`` converts the scale, but nothing converts the *variance*. A
    /// debug run shares a laptop with builds, editors and other agents' test runs, and
    /// the minimum of five repetitions does not save a figure whose every repetition
    /// was inflated together — that is how `set` on a 5000-node document reported
    /// 2626 ms against a 2000 ms debug limit on a machine that measured 1767 ms alone.
    /// Failing there reports the machine, not the code — however far over: a debug run
    /// once also failed past 4× the limit, and a loaded soak of the suite tripped that on
    /// a healthy `tree` (3063 ms against 750 ms, `project/2026-09-28-suite-speed.md`), so
    /// an advisory run only ever warns.
    public static let isStrict: Bool = isOptimized
        || ProcessInfo.processInfo.environment[strictEnvironmentVariable] != nil

    /// Decides what a measurement means: by ``admits(_:)``, then ``standing``, then
    /// ``isStrict``.
    ///
    /// - Parameter sample: The repetitions that were measured.
    /// - Returns: ``Verdict/pass`` inside the limit; otherwise the note or failure the
    ///   caller prints or records.
    public func verdict(_ sample: PerformanceSample) -> Verdict {
        guard !admits(sample.best) else { return .pass }
        if standing == .target { return .target(targetNote(sample)) }
        return Self.isStrict ? .failure(report(sample)) : .advisory(advisory(sample))
    }

    /// What a blown budget prints: the numbers, and what to do about them.
    ///
    /// - Parameter sample: The repetitions that were measured.
    /// - Returns: A message naming the budget, the measurement, and the next command.
    public func report(_ sample: PerformanceSample) -> String {
        let configuration = Self.isOptimized ? "release" : "debug"
        let scaling = Self.isOptimized
            ? ""
            : " (\(Self.milliseconds(release)) release × \(Self.debugMultiplier) debug multiplier)"
        let confirm: String = Self.isOptimized
            ? "Confirm it on a quiet machine, reading the figure beside `uptime` — a loaded"
            + " machine inflates even a minimum:"
            : "Confirm it on an optimized build — the budget is stated for one, and a loaded"
            + " machine inflates even a minimum:"
        return """
        \(name) took \(Self.milliseconds(sample.best)), over its \(Self.milliseconds(limit)) \
        budget on this \(configuration) build\(scaling).
        Samples: \(sample.summary).
        \(confirm)
          \(Self.confirmCommand)
        If release is also over, see which phase grew before touching the number:
          WOODCASE_TEST_PROFILE=1 swift test --filter PerformanceBudgets 2>&1 | grep PROFILE
        See WoodcasePerformance.md for what each budget covers and how it was set.
        """
    }

    /// The warning an advisory run prints for a measurement over ``limit``: how far over,
    /// and the run that settles whether the code or the machine is slow.
    ///
    /// - Parameter sample: The repetitions that were measured.
    /// - Returns: One `BUDGET-ADVISORY` line.
    public func advisory(_ sample: PerformanceSample) -> String {
        let ratio = sample.best / limit
        return "BUDGET-ADVISORY | \(name) | min \(Self.milliseconds(sample.best))"
            + " | \(String(format: "%.1f", ratio))× its \(Self.milliseconds(limit)) debug limit"
            + " | confirm with: \(Self.confirmCommand)"
            + " (or set $\(Self.strictEnvironmentVariable) to fail on this)"
    }

    /// The note a ``Standing/target`` budget prints for a measurement over ``limit``:
    /// how far the code still is from the target, and that nothing fails on it yet.
    ///
    /// - Parameter sample: The repetitions that were measured.
    /// - Returns: One `BUDGET-TARGET` line.
    public func targetNote(_ sample: PerformanceSample) -> String {
        let ratio = sample.best / limit
        return "BUDGET-TARGET | \(name) | min \(Self.milliseconds(sample.best))"
            + " | \(String(format: "%.1f", ratio))× its \(Self.milliseconds(limit)) target"
            + " | not enforced until the work that meets it lands"
    }

    /// One machine-readable line for a measurement, pass or fail.
    ///
    /// This is how the figures in `WoodcasePerformance.md` are produced — the release
    /// table is `swift run -c release WoodcaseBench budgets | grep BUDGET`. A budget
    /// that only spoke up when it failed would leave the doc's numbers to be re-derived
    /// by hand, and hand-derived numbers go stale silently.
    ///
    /// - Parameter sample: The repetitions that were measured.
    /// - Returns: One `BUDGET` line.
    public func announcement(_ sample: PerformanceSample) -> String {
        let configuration = Self.isOptimized ? "release" : "debug"
        return "BUDGET | \(name) | \(configuration) | min \(Self.milliseconds(sample.best))"
            + " | limit \(Self.milliseconds(limit)) | samples \(sample.summary)"
    }

    /// Formats a duration as milliseconds with one decimal.
    ///
    /// - Parameter duration: The duration to format.
    /// - Returns: A string such as `"87.4 ms"`.
    public static func milliseconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f ms", value)
    }
}
