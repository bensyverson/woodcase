//
//  PollingWait.swift
//  WoodcaseCommandTests
//

import Foundation
import Woodcase

/// A bounded poll for a condition some other process will make true, which also
/// reports how well it actually managed to look.
///
/// A test that waits on another process cannot await it; it can only look, sleep and
/// look again. Under the parallel suite the sleep is not the interval it asks for — a
/// test's continuation queues behind every other test's work on the cooperative pool,
/// and a 10 ms `Task.sleep` has been measured resuming twelve seconds later — so the
/// report carries the number of looks and the longest gap between two of them. A
/// failure that says "looked twice, 31 s apart" names the waiter, not the process it
/// was waiting for.
struct PollingWait: Friendly {
    /// What one wait saw.
    struct Outcome: Friendly {
        /// Whether the condition held at the last look.
        let satisfied: Bool

        /// How many times the condition was evaluated.
        let looks: Int

        /// The longest time between two consecutive looks, or from the start to the
        /// first look.
        let longestGap: Duration

        /// How long the whole wait took.
        let elapsed: Duration

        /// One sentence for a failure message.
        var summary: String {
            "looked \(looks) time(s) in \(elapsed.secondsText); longest gap between looks \(longestGap.secondsText)"
        }
    }

    /// How long to keep polling.
    let bound: Duration

    /// How long to suspend between looks.
    let poll: Duration

    /// Polls `condition` until it holds or ``bound`` has passed, then looks once more.
    ///
    /// - Parameter condition: The state being waited for.
    /// - Returns: What the wait saw.
    func until(_ condition: () -> Bool) async -> Outcome {
        let start = ContinuousClock.now
        let deadline = start + bound
        var looks = 0
        var lastLook = start
        var longestGap: Duration = .zero

        func look() -> Bool {
            let now = ContinuousClock.now
            longestGap = max(longestGap, now - lastLook)
            lastLook = now
            looks += 1
            return condition()
        }

        var satisfied = false
        while ContinuousClock.now < deadline {
            if look() {
                satisfied = true
                break
            }
            try? await Task.sleep(for: poll)
        }
        // The deadline bounds how long to wait, not whether to look: a sleep that
        // resumed past it may have slept straight through the condition coming true.
        if !satisfied {
            satisfied = look()
        }
        return Outcome(
            satisfied: satisfied, looks: looks, longestGap: longestGap,
            elapsed: ContinuousClock.now - start
        )
    }
}

private extension Duration {
    /// Seconds with millisecond precision, for a failure message.
    var secondsText: String {
        let (seconds, attoseconds) = components
        return String(format: "%.3f s", Double(seconds) + Double(attoseconds) / 1e18)
    }
}
