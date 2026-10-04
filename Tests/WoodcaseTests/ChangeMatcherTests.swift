//
//  ChangeMatcherTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``ChangeMatcher``: a file change is explained by the log rows for the same file,
/// whichever of the two arrives first, and a change nothing explains is released after
/// the window. Time is injected, so no test waits on a clock.
struct ChangeMatcherTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let path = "/Users/agent/Designs/demo.pen"

    private static func event(_ revision: String, file: String = path) -> ActivityEvent {
        ActivityEvent(
            time: start,
            identity: "claude",
            file: URL(fileURLWithPath: file),
            op: .set,
            nodes: ["jSUCH"],
            revision: revision
        )
    }

    @Test("An event already in hand matches the change at once")
    func inHandEventMatchesImmediately() {
        var matcher = ChangeMatcher(window: .seconds(2))
        #expect(matcher.logged(Self.event("r1")) == nil)
        let match = matcher.fileChanged(path: Self.path, at: Self.start)
        #expect(match?.events.map(\.revision) == ["r1"])
        #expect(matcher.waitingPaths.isEmpty)
        // Taken, not copied: the next change starts from nothing.
        #expect(matcher.fileChanged(path: Self.path, at: Self.start) == nil)
    }

    @Test("Every event queued for the file is taken by one change")
    func oneChangeTakesAllQueuedEvents() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.logged(Self.event("r1"))
        _ = matcher.logged(Self.event("r2"))
        _ = matcher.logged(Self.event("other", file: "/Users/agent/Designs/other.pen"))
        let match = matcher.fileChanged(path: Self.path, at: Self.start)
        #expect(match?.events.map(\.revision) == ["r1", "r2"])
    }

    @Test("A change with nothing logged waits, and a late event completes it")
    func lateEventCompletesAWaitingChange() {
        var matcher = ChangeMatcher(window: .seconds(2))
        #expect(matcher.fileChanged(path: Self.path, at: Self.start) == nil)
        #expect(matcher.waitingPaths == [Self.path])

        let match = matcher.logged(Self.event("r1"))
        #expect(match?.path == Self.path)
        #expect(match?.events.map(\.revision) == ["r1"])
        #expect(match?.changedAt == Self.start)
        #expect(matcher.waitingPaths.isEmpty)
    }

    @Test("A late event for another file leaves the change waiting")
    func lateEventForAnotherFileDoesNotComplete() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.fileChanged(path: Self.path, at: Self.start)
        #expect(matcher.logged(Self.event("x", file: "/Users/agent/Designs/other.pen")) == nil)
        #expect(matcher.waitingPaths == [Self.path])
    }

    @Test("A change nobody explains expires after the window, unattributed")
    func unexplainedChangeExpires() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.fileChanged(path: Self.path, at: Self.start)

        #expect(matcher.expire(now: Self.start.addingTimeInterval(1.9)).isEmpty)
        let expired = matcher.expire(now: Self.start.addingTimeInterval(2))
        #expect(expired.map(\.path) == [Self.path])
        #expect(expired.first?.events.isEmpty == true)
        #expect(expired.first?.isAttributed == false)
        #expect(matcher.waitingPaths.isEmpty)
    }

    @Test("An event that arrives after the window starts the next change's evidence")
    func eventAfterExpiryIsKeptForTheNextChange() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.fileChanged(path: Self.path, at: Self.start)
        _ = matcher.expire(now: Self.start.addingTimeInterval(3))

        #expect(matcher.logged(Self.event("late")) == nil)
        let match = matcher.fileChanged(path: Self.path, at: Self.start.addingTimeInterval(4))
        #expect(match?.events.map(\.revision) == ["late"])
    }

    @Test("A second change on a waiting path keeps the first one's clock")
    func repeatedChangeDoesNotRestartTheWindow() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.fileChanged(path: Self.path, at: Self.start)
        _ = matcher.fileChanged(path: Self.path, at: Self.start.addingTimeInterval(1.5))
        let expired = matcher.expire(now: Self.start.addingTimeInterval(2))
        #expect(expired.count == 1)
    }

    @Test("Whether a path is waiting tracks the change until something claims it")
    func isWaitingTracksTheChange() {
        var matcher = ChangeMatcher(window: .seconds(2))
        #expect(!matcher.isWaiting(Self.path))
        _ = matcher.fileChanged(path: Self.path, at: Self.start)
        #expect(matcher.isWaiting(Self.path))
        _ = matcher.logged(Self.event("r1"))
        #expect(!matcher.isWaiting(Self.path))
    }

    @Test("An abandoned change leaves no clock for the next one")
    func abandonedChangeForgetsItsClock() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.fileChanged(path: Self.path, at: Self.start)
        matcher.abandon(path: Self.path)
        #expect(matcher.waitingPaths.isEmpty)

        _ = matcher.fileChanged(path: Self.path, at: Self.start.addingTimeInterval(10))
        #expect(matcher.expire(now: Self.start.addingTimeInterval(11)).isEmpty)
    }
}
