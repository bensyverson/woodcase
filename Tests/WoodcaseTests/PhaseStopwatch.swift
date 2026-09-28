import Foundation

/// A running stopwatch that prints one line per phase of a slow test.
///
/// The WebView regression suite is the slowest thing in the run, and the only
/// way to learn *which* of its phases costs the seconds — the page host, the
/// load, the ready wait, the emitter, the pixel render, the MAE — is to time
/// each one where it happens. Instrumentation that has to be re-added every
/// time someone measures gets re-added wrong, so this stays, switched off by
/// default: when ``isEnabled`` is false a lap is one comparison and no
/// allocation.
///
/// ```sh
/// WOODCASE_TEST_PROFILE=1 swift test --filter WebViewRegression 2>&1 | grep PROFILE
/// ```
///
/// Each line is `PROFILE <scope> <phase> <milliseconds>`, so the output is
/// directly summable with `awk`.
struct PhaseStopwatch {
    /// Whether laps are printed.
    ///
    /// Read once per process: the environment does not change mid-run, and a
    /// lap must not pay for a dictionary lookup.
    static let isEnabled: Bool = ProcessInfo.processInfo.environment["WOODCASE_TEST_PROFILE"] != nil

    /// What the phases belong to — a component name, a screen name, an HTML
    /// file. Printed on every line so a parallel run stays readable.
    private let scope: String

    /// When the previous lap ended, which is when this one began.
    private var last: ContinuousClock.Instant

    /// When the stopwatch started, for ``total()``.
    private let began: ContinuousClock.Instant

    /// Starts a stopwatch for `scope`.
    ///
    /// - Parameter scope: the label every line of this stopwatch carries.
    init(_ scope: String) {
        self.scope = scope
        let now: ContinuousClock.Instant = ContinuousClock.now
        last = now
        began = now
    }

    /// Ends the phase named `phase` and starts the next one.
    ///
    /// - Parameter phase: what the time since the last lap was spent on.
    mutating func lap(_ phase: String) {
        let now: ContinuousClock.Instant = ContinuousClock.now
        defer { last = now }
        guard Self.isEnabled else { return }
        Self.report(scope: scope, phase: phase, elapsed: last.duration(to: now))
    }

    /// Prints everything since ``init(_:)`` as a `total` line.
    func total() {
        guard Self.isEnabled else { return }
        Self.report(scope: scope, phase: "total", elapsed: began.duration(to: ContinuousClock.now))
    }

    /// Prints one profile line.
    private static func report(scope: String, phase: String, elapsed: Duration) {
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        print("PROFILE \(scope) \(phase) \(String(format: "%.1f", milliseconds))")
    }
}
