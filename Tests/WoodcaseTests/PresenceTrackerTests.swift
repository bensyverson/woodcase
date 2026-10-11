//
//  PresenceTrackerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins the library's ``PresenceTracker``: who is present, in what stable order, and
/// which node each identity touched last.
struct PresenceTrackerTests {
    private static let file = URL(fileURLWithPath: "/tmp/demo.pen")

    private func event(
        _ identity: String,
        at seconds: TimeInterval,
        op: ActivityEvent.Kind = .set,
        nodes: [String] = [],
        paths: [String] = [],
        file: URL = file,
        revision: String = "r",
        batch: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: seconds),
            identity: identity,
            file: file,
            op: op,
            nodes: nodes,
            paths: paths,
            revision: revision,
            batch: batch
        )
    }

    @Test("An empty tracker has no identities")
    func startsEmpty() {
        let tracker = PresenceTracker()
        #expect(tracker.isEmpty)
        #expect(tracker.snapshot().identities.isEmpty)
    }

    @Test("Identities are ordered by first appearance, and the order never changes")
    func ordersByFirstAppearance() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10))
        tracker.record(event("ben", at: 20))
        tracker.record(event("ana", at: 30))
        tracker.record(event("cy", at: 5))

        let identities = tracker.snapshot().identities
        #expect(identities.map(\.name) == ["ana", "ben", "cy"])
        #expect(identities.map(\.order) == [0, 1, 2])
    }

    @Test("A registered identity takes its place in the order before it has done anything")
    func registersWithoutAnEvent() {
        var tracker = PresenceTracker()
        tracker.register("ben")
        tracker.record(event("ana", at: 10))
        tracker.register("ben")

        var identities = tracker.snapshot().identities
        #expect(identities.map(\.name) == ["ben", "ana"])
        #expect(identities.map(\.order) == [0, 1])
        #expect(identities[0].changes == 0)
        #expect(identities[0].files.isEmpty)
        #expect(identities[0].lastSeen == .distantPast)
        #expect(identities[0].latestChange == nil)

        tracker.record(event("ben", at: 40))
        identities = tracker.snapshot().identities
        #expect(identities[0].order == 0)
        #expect(identities[0].changes == 1)
        #expect(identities[0].lastSeen == Date(timeIntervalSince1970: 40))
    }

    @Test("Last seen is the newest event's time and the count accumulates")
    func tallies() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10))
        tracker.record(event("ana", at: 40))

        let identity = tracker.snapshot().identities[0]
        #expect(identity.changes == 2)
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
        let a = URL(fileURLWithPath: "/tmp/a.pen")
        let b = URL(fileURLWithPath: "/tmp/b.pen")
        tracker.record(event("ana", at: 10, file: a))
        tracker.record(event("ana", at: 20, file: b))
        tracker.record(event("ana", at: 30, file: a))

        let expected = [a, b].map(ActivityEvent.canonicalPath(for:))
        #expect(tracker.snapshot().identities[0].files == expected)
    }

    @Test("A batch yields one latest change with its subject node first")
    func oneMarkPerBatch() throws {
        var tracker = PresenceTracker()
        tracker.record(event(
            "ana", at: 10, nodes: ["A", "P"], paths: ["Home/A", "Home"], revision: "r1", batch: "b1"
        ))
        tracker.record(event(
            "ana", at: 11, op: .mv, nodes: ["B", "P"], paths: ["Home/B", "Home"], revision: "r2", batch: "b1"
        ))

        let identity = tracker.snapshot().identities[0]
        let mark = try #require(identity.latestChange)
        #expect(identity.changes == 2)
        #expect(mark.nodes == ["A", "P", "B"])
        #expect(mark.paths == ["Home/A", "Home", "Home/B"])
        #expect(mark.revision == "r2")
        #expect(mark.time == Date(timeIntervalSince1970: 11))
        #expect(mark.op == nil, "a batch of mixed operations has no single verb")
    }

    @Test("A new batch replaces the latest change")
    func newBatchReplacesTheMark() throws {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10, nodes: ["A"], batch: "b1"))
        tracker.record(event("ana", at: 20, op: .rm, nodes: ["Z"], batch: "b2"))

        let mark = try #require(tracker.snapshot().identities[0].latestChange)
        #expect(mark.nodes == ["Z"])
        #expect(mark.op == .rm)
    }

    @Test("Events with no batch each stand alone")
    func unbatchedEventsStandAlone() throws {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10, nodes: ["A"]))
        tracker.record(event("ana", at: 20, nodes: ["B"]))

        let mark = try #require(tracker.snapshot().identities[0].latestChange)
        #expect(mark.nodes == ["B"])
    }

    @Test("A row that names no node updates last-seen only")
    func nodelessRowKeepsTheMark() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10, nodes: ["A"], batch: "b1"))
        tracker.record(event("ana", at: 50, op: .var, nodes: [], batch: "b2"))

        let identity = tracker.snapshot().identities[0]
        #expect(identity.lastSeen == Date(timeIntervalSince1970: 50))
        #expect(identity.changes == 2)
        #expect(identity.latestChange?.nodes == ["A"])
    }

    @Test("A mark holds at most 32 nodes, subject first")
    func marksAreCapped() throws {
        var tracker = PresenceTracker()
        let nodes = (0 ..< 40).map { "n\($0)" }
        tracker.record(event("ana", at: 10, nodes: nodes, paths: nodes))

        let mark = try #require(tracker.snapshot().identities[0].latestChange)
        #expect(mark.nodes.count == 32)
        #expect(mark.paths.count == 32)
        #expect(mark.nodes.first == "n0")
    }

    @Test("The cursor node is the latest change's subject")
    func cursorNodeFollowsTheLatestChange() {
        var tracker = PresenceTracker()
        tracker.record(event("ana", at: 10, nodes: ["A", "P"]))
        #expect(tracker.snapshot().identities[0].cursorNode == "A")

        var empty = PresenceTracker()
        empty.record(event("ben", at: 10))
        #expect(empty.snapshot().identities[0].cursorNode == nil)
    }
}
