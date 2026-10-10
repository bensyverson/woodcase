//
//  ChangeMatcherRowExpiryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins the two things a single-file follower needs from ``ChangeMatcher`` beyond what
/// the viewer uses: a row filed under the path the follower watches, whatever path the
/// row itself names, and a row no change claimed being released after the window
/// instead of explaining some later, unrelated change.
struct ChangeMatcherRowExpiryTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let watched = "/Users/agent/Designs/Design.umbra/document.pen"

    private static func event(_ revision: String, file: String = "/Users/agent/Old.umbra/document.pen") -> ActivityEvent {
        ActivityEvent(
            time: start,
            identity: "claude",
            file: URL(fileURLWithPath: file),
            op: .set,
            nodes: ["jSUCH"],
            revision: revision
        )
    }

    @Test("A row logged under an explicit path explains that path's change")
    func explicitPathKeysTheRow() {
        var matcher = ChangeMatcher(window: .seconds(2))
        #expect(matcher.logged(Self.event("r1"), path: Self.watched, at: Self.start) == nil)
        let match = matcher.fileChanged(path: Self.watched, at: Self.start)
        #expect(match?.events.map(\.revision) == ["r1"])
        // The row is delivered as written: only the key moved.
        #expect(match?.events.first?.file == "/Users/agent/Old.umbra/document.pen")
    }

    @Test("A row logged under an explicit path completes a change waiting on that path")
    func explicitPathCompletesAWaitingChange() {
        var matcher = ChangeMatcher(window: .seconds(2))
        #expect(matcher.fileChanged(path: Self.watched, at: Self.start) == nil)
        let match = matcher.logged(Self.event("r1"), path: Self.watched, at: Self.start)
        #expect(match?.path == Self.watched)
        #expect(match?.events.map(\.revision) == ["r1"])
    }

    @Test("A row no change claims is released once the window has passed since it arrived")
    func unclaimedRowExpires() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.logged(Self.event("r1"), path: Self.watched, at: Self.start)
        _ = matcher.logged(Self.event("r2"), path: Self.watched, at: Self.start.addingTimeInterval(1.5))

        #expect(matcher.expireEvents(now: Self.start.addingTimeInterval(1.9)).isEmpty)
        #expect(matcher.expireEvents(now: Self.start.addingTimeInterval(2)).map(\.revision) == ["r1"])
        #expect(matcher.expireEvents(now: Self.start.addingTimeInterval(3.5)).map(\.revision) == ["r2"])
        // Released, not copied: the next change finds nothing in hand.
        #expect(matcher.fileChanged(path: Self.watched, at: Self.start.addingTimeInterval(4)) == nil)
    }

    @Test("A row logged without an arrival time never expires")
    func untimedRowStays() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.logged(Self.event("r1", file: Self.watched))
        #expect(matcher.expireEvents(now: Self.start.addingTimeInterval(3600)).isEmpty)
        #expect(matcher.fileChanged(path: Self.watched, at: Self.start)?.events.map(\.revision) == ["r1"])
    }

    @Test("A row claimed by a change is not released again")
    func claimedRowDoesNotExpire() {
        var matcher = ChangeMatcher(window: .seconds(2))
        _ = matcher.logged(Self.event("r1"), path: Self.watched, at: Self.start)
        _ = matcher.fileChanged(path: Self.watched, at: Self.start)
        #expect(matcher.expireEvents(now: Self.start.addingTimeInterval(10)).isEmpty)
    }
}
