//
//  ParentProcessWatchTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// ``ParentProcessWatch`` records its launcher when it is made, not when it starts
/// waiting.
///
/// The gap between the two is the bug these pin: `activity --follow` used to read its
/// parent only once its follow loop was running, after it had already printed. A
/// launcher that exits the moment it sees that output — which is what
/// `followStopsWhenOrphaned` does — could be gone by then, so the watch recorded
/// `launchd` as the launcher, took itself for a process born orphaned, and never
/// returned.
@Suite("Parent process watch")
struct ParentProcessWatchTests {
    @Test("A new watch records this process's current parent")
    func recordsTheParentWhenMade() {
        #expect(ParentProcessWatch().launcher == getppid())
    }

    @Test("A watch whose launcher is no longer the parent returns at once")
    func returnsWhenTheRecordedLauncherIsGone() async {
        // Any pid above 1 that is not our parent stands for a launcher that has died:
        // the kernel would have reparented us away from it.
        let gone = ParentProcessWatch(launcher: getppid() + 1)
        #expect(gone.isOrphaned)

        let started = ContinuousClock.now
        await gone.waitUntilOrphaned(pollInterval: .milliseconds(10))
        // "Returned at all" is the assertion; the bound only says "not hung".
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    @Test("A watch made after the launcher was already gone never fires")
    func bornOrphanedIsNeverWatched() {
        #expect(!ParentProcessWatch(launcher: 1).isOrphaned)
        #expect(!ParentProcessWatch(launcher: 0).isOrphaned)
    }

    @Test("A watch on the live parent does not fire")
    func liveParentIsNotOrphaned() {
        #expect(!ParentProcessWatch(launcher: getppid()).isOrphaned)
    }
}
