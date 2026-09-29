//
//  ScriptWatchdog.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Synchronization

/// Ends the process when a script outstays its `--timeout`.
///
/// The host's own budget is a *deadline* that every bridged call checks, so it bounds
/// every script that does work: past it, the next `doc.*` call throws. It does not bound
/// `while (true) {}`, which calls nothing — and the public JavaScriptCore headers on
/// macOS 15 carry no execution-time limit and no interrupt to ask for (checked
/// 2026-09-07). So the CLI adds the last resort: a thread that outlives the deadline by
/// a short grace, says what happened on standard error, and exits 3.
///
/// **It is the CLI's and never the library's.** A host that called `exit` inside
/// Penumbra would take the editor with it; a library consumer that needs a hard bound on
/// a pure loop runs the host out of process.
///
/// **A thread, not a `Task`.** A `while (true) {}` in JavaScriptCore never yields, so a
/// cooperative-pool task scheduled beside it may never run. A `Thread` is the operating
/// system's to schedule and runs regardless.
///
/// **Killing the process loses nothing.** ``Woodcase/PenFileTransaction`` writes no
/// bytes until its body returns, and the advisory `flock` is the kernel's to release, so
/// a script cut off mid-run leaves the file and the activity log exactly as they were —
/// which is what the sentence says.
///
/// ```swift
/// let watchdog = ScriptWatchdog(timeout: .seconds(30))
/// watchdog.start()
/// defer { watchdog.cancel() }
/// ```
final class ScriptWatchdog: Sendable {
    /// How long past the deadline the watchdog waits before ending the process.
    ///
    /// The host refuses on the *next* bridged call, so a script inside a long one — a
    /// `doc.tree()` settling a large document — is over its deadline for as long as that
    /// call takes to come back and unwind. The grace is the margin that keeps the
    /// watchdog from shooting a run that was about to stop on its own, and it is short
    /// because everything it protects is already past its budget.
    static let grace: Duration = .seconds(2)

    /// Arms a watchdog for one run.
    ///
    /// - Parameter timeout: The script's budget, as `--timeout` gave it. The thread
    ///   fires at this plus ``grace``.
    init(timeout: Duration) {
        self.timeout = timeout
        sentence = "script ran past \(ScriptWatchdog.seconds(timeout)) s; nothing was written"
    }

    /// The script's budget.
    let timeout: Duration

    /// What the watchdog says before it ends the process.
    let sentence: String

    /// Starts the thread. Call once.
    func start() {
        let deadline = ContinuousClock.now.advanced(by: timeout + Self.grace)
        let thread = Thread { [self] in
            while ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: Self.pollInterval)
                if canceled.withLock({ $0 }) { return }
            }
            fire()
        }
        thread.name = "woodcase.js.watchdog"
        thread.start()
    }

    /// Stands the watchdog down, because the run finished first.
    ///
    /// Taking the lock is what closes the race: a watchdog that has already decided to
    /// fire holds it until the process is gone, so `cancel` can never arrive between the
    /// decision and the exit.
    func cancel() {
        canceled.withLock { $0 = true }
    }

    // MARK: - Private

    /// How often the thread wakes to notice it has been canceled.
    ///
    /// Fast enough that a finished run's process is not held open by it, slow enough to
    /// cost nothing over a long script.
    private static let pollInterval: TimeInterval = 0.05

    /// Whether the run finished before the deadline.
    private let canceled = Mutex(false)

    /// Says what happened and ends the process, unless the run beat it to the line.
    private func fire() {
        canceled.withLock { canceled in
            guard !canceled else { return }
            StandardError.write(sentence)
            exit(ExitCode.conflict.rawValue)
        }
    }

    /// A budget as the whole number of seconds the sentence names, where it is one.
    ///
    /// `--timeout 30` reads `past 30 s`, not `past 30.0 s`; a fractional budget keeps
    /// its fraction rather than rounding to a number the caller did not write.
    private static func seconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
    }
}
