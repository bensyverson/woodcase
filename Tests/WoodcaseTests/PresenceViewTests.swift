//
//  PresenceViewTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins how ``PresenceTracker`` folds reads in: a view sets the reader's latest view,
/// never its change count, and the cursor goes wherever the newer of the two marks is.
struct PresenceViewTests {
    private static let file = URL(fileURLWithPath: "/tmp/demo.pen")

    private func view(_ identity: String, at seconds: TimeInterval, nodes: [String], revision: String = "r1") -> ViewEvent {
        ViewEvent(
            time: Date(timeIntervalSince1970: seconds), identity: identity, file: Self.file,
            verb: .get, revision: revision, nodes: nodes
        )
    }

    private func change(_ identity: String, at seconds: TimeInterval, nodes: [String]) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: seconds), identity: identity, file: Self.file,
            op: .set, nodes: nodes, revision: "r2"
        )
    }

    @Test("A view sets the reader's latest view, and is not counted as a change")
    func viewSetsLatestView() throws {
        var tracker = PresenceTracker()
        tracker.record(view("claude", at: 10, nodes: ["A", "B"]))

        let identity = try #require(tracker.snapshot().identities.first)
        #expect(identity.name == "claude")
        #expect(identity.changes == 0)
        #expect(identity.latestChange == nil)
        #expect(identity.latestView?.nodes == ["A", "B"])
        #expect(identity.latestView?.revision == "r1")
        #expect(identity.latestView?.verb == .get)
        #expect(identity.lastSeen == Date(timeIntervalSince1970: 10))
        #expect(identity.files == [Self.file.standardizedFileURL.resolvingSymlinksInPath().path])
    }

    @Test("A newer view replaces the latest view")
    func newerViewReplaces() {
        var tracker = PresenceTracker()
        tracker.record(view("claude", at: 10, nodes: ["A"]))
        tracker.record(view("claude", at: 11, nodes: ["B"]))
        #expect(tracker.snapshot().identities[0].latestView?.nodes == ["B"])
    }

    @Test("The cursor goes to the newer of the latest change and the latest view")
    func cursorFollowsTheNewerMark() {
        var tracker = PresenceTracker()
        tracker.record(change("claude", at: 10, nodes: ["C"]))
        tracker.record(view("claude", at: 11, nodes: ["V"]))
        #expect(tracker.snapshot().identities[0].cursorNode == "V")

        tracker.record(change("claude", at: 12, nodes: ["C2"]))
        #expect(tracker.snapshot().identities[0].cursorNode == "C2")
    }

    @Test("A reader who never wrote keeps their order of first appearance")
    func readersTakeAnOrder() {
        var tracker = PresenceTracker()
        tracker.record(change("ana", at: 10, nodes: ["A"]))
        tracker.record(view("claude", at: 11, nodes: ["B"]))
        tracker.record(change("claude", at: 12, nodes: ["C"]))
        #expect(tracker.snapshot().identities.map(\.name) == ["ana", "claude"])
        #expect(tracker.snapshot().identities[1].changes == 1)
    }

    @Test("A follower's events fold in: changes, activity and views alike")
    func followerEventsFoldIn() {
        var tracker = PresenceTracker()
        tracker.record(PenFileFollower.Event.changed(PenFileFollower.FileChange(
            events: [change("ana", at: 10, nodes: ["A"])], changedAt: Date(timeIntervalSince1970: 10)
        )))
        tracker.record(PenFileFollower.Event.activity(change("bo", at: 11, nodes: ["B"])))
        tracker.record(PenFileFollower.Event.viewed(view("claude", at: 12, nodes: ["C"])))
        tracker.record(PenFileFollower.Event.restarted)

        let identities = tracker.snapshot().identities
        #expect(identities.map(\.name) == ["ana", "bo", "claude"])
        #expect(identities.map(\.cursorNode) == ["A", "B", "C"])
    }
}
