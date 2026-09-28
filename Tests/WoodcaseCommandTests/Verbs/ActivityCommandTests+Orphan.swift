//
//  ActivityCommandTests+Orphan.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

extension ActivityCommandTests {
    /// How long an orphaned follower is given to notice and exit — "not hung" scale,
    /// since its own poll is 250 ms.
    static let orphanExitBudget: Duration = .seconds(30)

    /// What the launcher shell reports by its exit status.
    enum LauncherStatus: Int32, Friendly {
        /// The follower printed, so it had recorded its launcher before the shell left.
        case sawOutput = 0

        /// The follower printed nothing in the shell's whole wait. It may not have
        /// reached the point where it records its launcher, so it may take itself for
        /// one born orphaned — which it is right to ignore.
        case gaveUp = 3
    }

    @Test("--follow stops when the process that launched it goes away")
    func followStopsWhenOrphaned() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let binary = try CommandFixture.binary()
        let pidURL = fixture.root.appendingPathComponent("follow-pid.txt")
        let stdoutURL = fixture.root.appendingPathComponent("orphan-stdout.txt")
        let stderrURL = fixture.root.appendingPathComponent("orphan-stderr.txt")

        // One event already in the log, so the follower prints something the moment it
        // is up and the shell below can tell that it is.
        try await Self.recordRename(fixture, as: "ana", name: "before-the-follow")

        // A shell that starts the follower, waits only until it is running, and then
        // exits — leaving it orphaned exactly the way a killed test run does. Waiting
        // matters: a follower that was *born* orphaned has no parent's death to notice
        // and is left alone deliberately, so `nohup woodcase activity --follow &` keeps
        // working. The follower prints only after recording its launcher, so output is
        // proof the shell's exit will be noticed.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = [
            "-c",
            """
            "$1" activity --follow > "$2" 2> "$4" &
            echo $! > "$3"
            n=0
            while [ ! -s "$2" ] && [ $n -lt 1200 ]; do sleep 0.05; n=$((n+1)); done
            [ -s "$2" ] || exit \(LauncherStatus.gaveUp.rawValue)
            """,
            "sh", binary.path, stdoutURL.path, pidURL.path, stderrURL.path,
        ]
        launcher.environment = Self.followEnvironment(fixture)
        try launcher.run()
        let launcherWait = await PollingWait(bound: .seconds(120), poll: .milliseconds(20)).until {
            !launcher.isRunning
        }
        let launcherSeenGone = ContinuousClock.now

        let recorded = (try? String(contentsOf: pidURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let follower = try #require(
            recorded.flatMap { pid_t($0) }, "the launcher should write the follower's pid"
        )
        guard launcherWait.satisfied else {
            launcher.terminate()
            kill(follower, SIGKILL)
            Issue.record("the launcher shell never exited: \(launcherWait.summary)")
            return
        }
        guard launcher.terminationStatus == LauncherStatus.sawOutput.rawValue else {
            kill(follower, SIGKILL)
            Issue.record("""
            the launcher exited \(launcher.terminationStatus) \
            (\(LauncherStatus.gaveUp.rawValue) = the follower printed nothing in its whole wait), \
            so the follower may never have recorded a launcher to outlive. \
            Follower stderr: \(Self.contents(of: stderrURL))
            """)
            return
        }

        let exitWait = await PollingWait(bound: Self.orphanExitBudget, poll: .milliseconds(100)).until {
            kill(follower, 0) != 0 && errno == ESRCH
        }
        guard !exitWait.satisfied else { return }

        // Still alive: say why before killing it, so the failure names its own cause.
        let sinceLauncher = ContinuousClock.now - launcherSeenGone
        let snapshot = await ProcessSnapshot.take(of: follower, in: fixture.root)
        kill(follower, SIGKILL)
        Issue.record("""
        an orphaned `activity --follow` must exit on its own. \
        Its launcher (pid \(launcher.processIdentifier)) was seen gone \(sinceLauncher) ago; \
        the waiter \(exitWait.summary).
        ps:
        \(snapshot.ps)
        follower stderr: \(Self.contents(of: stderrURL))
        follower stdout: \(Self.contents(of: stdoutURL))
        sample:
        \(snapshot.sample)
        """)
    }

    /// A file's text for a failure message, or a note that there is none.
    ///
    /// - Parameter url: The file to read.
    /// - Returns: Its contents, or "(empty)" / "(unreadable)".
    private static func contents(of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "(unreadable)" }
        return text.isEmpty ? "(empty)" : text
    }
}
