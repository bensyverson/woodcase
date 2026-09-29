//
//  ParentProcessWatch.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Notices when the process that launched this one has gone away.
///
/// A verb that never ends on its own — today only `activity --follow` — has no other
/// way to learn that nobody is reading it any more. A signal is not enough on its own:
/// the launcher may be killed rather than exit, or may die between two of its own
/// polls, and what it leaves behind is a `woodcase` that runs forever, holding its
/// working directory open and reading a log nobody will ever see. Every orphan of that
/// shape observed in this project came out of a test run, and each one cost the *next*
/// run a lock timeout.
///
/// The check is `getppid()`. When the launcher dies the kernel reparents this process —
/// to `launchd` on Darwin, to `init` or the nearest subreaper on Linux — so a parent id
/// that is no longer the one recorded at the start means the launcher is gone. A
/// process that was *already* orphaned when it started (`nohup woodcase … &`, a launch
/// agent, a service manager) has nobody to outlive, and is never watched: for it, the
/// wait simply never finishes.
///
/// *When* the launcher is recorded is the whole contract. Make the watch before the
/// verb prints anything: a launcher may reasonably wait for the first line of output
/// and exit on it, and a watch that read `getppid()` only after that line — once its
/// loop was running — sees `launchd` already, takes itself for a process born orphaned
/// and never returns. The gap between the print and a late read is only milliseconds,
/// but a busy machine stretches it past the moment such a launcher exits.
struct ParentProcessWatch: Friendly {
    /// How often the parent id is re-read.
    ///
    /// Fast enough that an orphan is gone well inside a test's teardown, slow enough
    /// that a day-long `--follow` costs nothing measurable.
    static let pollInterval: Duration = .milliseconds(250)

    /// The parent id recorded when the watch was made.
    let launcher: pid_t

    /// Records this process's parent, as it is right now, as the launcher to outlive.
    init() {
        self.init(launcher: getppid())
    }

    /// Watches for `launcher` to stop being this process's parent.
    ///
    /// - Parameter launcher: The parent id to outlive; 1 or less means none.
    init(launcher: pid_t) {
        self.launcher = launcher
    }

    /// Whether ``launcher`` has stopped being this process's parent.
    ///
    /// A ``launcher`` of 1 or less is the already-orphaned case — `launchd` or `init`
    /// adopted this process before the watch was made, so there is no death left to
    /// notice, and this always answers `false`.
    var isOrphaned: Bool {
        launcher > 1 && getppid() != launcher
    }

    /// Suspends until ``launcher`` has gone away.
    ///
    /// Returns early if the surrounding task is canceled, which is how the caller
    /// takes the watch down when the work it was guarding finishes first.
    ///
    /// - Parameter pollInterval: How often to re-read the parent id.
    func waitUntilOrphaned(pollInterval: Duration = Self.pollInterval) async {
        while !isOrphaned {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return
            }
        }
    }
}
