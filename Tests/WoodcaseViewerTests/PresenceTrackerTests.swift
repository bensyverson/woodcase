//
//  PresenceTrackerTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

struct PresenceTrackerTests {
    private func event(_ identity: String, at seconds: TimeInterval) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: seconds),
            identity: identity,
            file: URL(fileURLWithPath: "/tmp/demo.pen"),
            op: .set,
            revision: "r"
        )
    }

    @Test("An empty tracker has no identities")
    func startsEmpty() {
        let tracker = PresenceTracker()
        #expect(tracker.isEmpty)
        #expect(tracker.snapshot().identities.isEmpty)
    }

    @Test("Identities are ordered by first appearance, which is what the page colors by")
    func ordersByFirstAppearance() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10))
        tracker.record(event("ben", at: 20))
        tracker.record(event("ana", at: 30))

        #expect(tracker.snapshot().identities.map(\.name) == ["ana", "ben"])
    }

    @Test("Last seen is the newest event's time and the count accumulates")
    func tallies() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10))
        tracker.record(event("ana", at: 40))

        let identity = tracker.snapshot().identities[0]
        #expect(identity.events == 2)
        #expect(identity.lastSeen == Date(timeIntervalSince1970: 40))
    }

    @Test("An event that arrives out of order does not move last-seen backwards")
    func doesNotGoBackwards() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 40))
        tracker.record(event("ana", at: 10))

        #expect(tracker.snapshot().identities[0].lastSeen == Date(timeIntervalSince1970: 40))
    }

    @Test("Files are listed most recently touched first, without repeats")
    func listsFilesMostRecentFirst() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10), fileID: "aaa")
        tracker.record(event("ana", at: 20), fileID: "bbb")
        tracker.record(event("ana", at: 30), fileID: "aaa")

        #expect(tracker.snapshot().identities[0].files == ["aaa", "bbb"])
    }
}
