//
//  TimeLimitTrait+HangGuard.swift
//  WoodcaseTests
//

import Testing

extension Trait where Self == TimeLimitTrait {
    /// The per-test time limit on every suite that awaits a page, a server or a feed:
    /// a test stuck past it is cancelled and fails by name instead of wedging the run.
    ///
    /// Sized against two numbers. A healthy test's wall time is not its own work: every
    /// browser test runs on the main actor, interleaved with every other, so the
    /// slowest reports about 80 % of the whole run (78 s of a 94 s run, 2026-09-08 suite
    /// logs), and a run at load 200 takes about 3 minutes. And the agents' watchdog
    /// kills a run at 10 minutes (`project/gotchas.md`), so a limit at or past it would
    /// never get to name anything. Eight minutes is past every healthy test the watchdog
    /// lets finish, and short of the watchdog. Swift Testing counts limits in whole
    /// minutes.
    static var hangGuard: Self {
        .timeLimit(.minutes(8))
    }
}
