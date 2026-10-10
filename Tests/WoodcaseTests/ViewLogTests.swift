//
//  ViewLogTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``ViewLog`` and ``ViewReader``: views go to `views.jsonl` beside the activity
/// log and never into it, the file rotates on its own, a repeated read of what was
/// already recorded is coalesced away, and a reader resumes from a cursor.
struct ViewLogTests {
    private static let file = URL(fileURLWithPath: "/tmp/ViewLogTests/design.pen")

    private func home() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewLogTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func view(
        _ identity: String = "claude",
        revision: String = "r1",
        nodes: [String],
        scope: ViewEvent.Scope = .nodes,
        verb: ViewEvent.Verb = .get,
        file: URL = file
    ) -> ViewEvent {
        ViewEvent(identity: identity, file: file, verb: verb, revision: revision, nodes: nodes, scope: scope)
    }

    @Test("A view round-trips through its line")
    func roundTrips() throws {
        let event = ViewEvent(
            time: Date(timeIntervalSince1970: 1_800_000_000.123),
            identity: "claude", file: Self.file, verb: .tree, revision: "r1",
            nodes: ["a", "b"], scope: .subtrees, covered: 12
        )
        let line = try event.jsonLine()
        #expect(try ViewEvent(line: line, using: JSONDecoder()) == event)
        let text = try #require(String(data: line, encoding: .utf8))
        #expect(text.contains(#""verb":"tree""#))
        #expect(text.contains(#""scope":"subtrees""#))
        #expect(text.contains(#""covered":12"#))
    }

    @Test("A view keeps at most 64 nodes, and covered counts what the read covered")
    func nodesAreCapped() {
        let nodes = (0 ..< 100).map { "n\($0)" }
        let event = view(nodes: nodes)
        #expect(event.nodes == Array(nodes.prefix(64)))
        #expect(event.covered == 100)
    }

    @Test("Views go to views.jsonl beside the activity log, never into it")
    func viewsLiveBesideActivity() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let activity = ActivityLog(home: home)
        let views = ViewLog(beside: activity)

        try await views.record(view(nodes: ["a"]))

        #expect(views.fileURL == home.appendingPathComponent("views.jsonl"))
        #expect(!FileManager.default.fileExists(atPath: activity.fileURL.path))
        #expect(try ViewReader(log: views).read().events.map(\.nodes) == [["a"]])
    }

    @Test("views.jsonl rotates on its own, and its archives are not the activity log's")
    func rotatesOnItsOwn() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let activity = ActivityLog(home: home)
        let views = ViewLog(beside: activity)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(repeating: 0x0A, count: Int(ViewLog.rotationThreshold) + 1).write(to: views.fileURL)
        try await activity.append([ActivityEvent(
            time: Date(), identity: "ana", file: Self.file, op: .set, revision: "r0"
        )])

        try await views.record(view(nodes: ["a"]))

        let names = try FileManager.default.contentsOfDirectory(atPath: home.path).sorted()
        #expect(names.count == 3)
        #expect(names.contains("activity.jsonl"))
        #expect(names.contains("views.jsonl"))
        #expect(names.contains { $0.hasPrefix("views.") && $0 != "views.jsonl" })
        #expect(activity.archives().isEmpty)
        #expect(try ViewReader(log: views).read().events.count == 1)
    }

    @Test("A same-revision read of nodes already recorded is coalesced away")
    func subsetReadIsCoalesced() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let views = ViewLog(home: home)

        #expect(try await views.record(view(nodes: ["a", "b"])))
        #expect(try await !views.record(view(nodes: ["b"])))
        #expect(try await !views.record(view(nodes: ["a", "b"], verb: .tree)))

        #expect(try ViewReader(log: views).read().events.count == 1)
    }

    @Test("A read that adds a node, moves the revision, widens to subtrees or comes from someone else is recorded")
    func newInformationIsRecorded() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let views = ViewLog(home: home)

        #expect(try await views.record(view(nodes: ["a"])))
        #expect(try await views.record(view(nodes: ["a", "b"])))
        #expect(try await views.record(view(revision: "r2", nodes: ["a"])))
        #expect(try await views.record(view(revision: "r2", nodes: ["a"], scope: .subtrees)))
        #expect(try await views.record(view("ana", revision: "r2", nodes: ["a"])))
        // A node read after its subtree was: already covered.
        #expect(try await !views.record(view(revision: "r2", nodes: ["a"])))

        #expect(try ViewReader(log: views).read().events.count == 5)
    }

    @Test("A reader resumes after its cursor and filters by file and identity")
    func readerResumesAndFilters() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let views = ViewLog(home: home)
        let reader = ViewReader(log: views)
        try await views.record(view(nodes: ["a"]))
        let first = try reader.read()

        try await views.record(view("ana", nodes: ["b"]))
        try await views.record(view(nodes: ["c"], file: URL(fileURLWithPath: "/tmp/ViewLogTests/other.pen")))
        try await views.record(view(nodes: ["d"]))

        let cursor = try #require(first.cursor)
        #expect(try reader.read(after: cursor).events.map(\.nodes) == [["b"], ["c"], ["d"]])
        #expect(try reader.read(after: cursor, file: Self.file).events.map(\.nodes) == [["b"], ["d"]])
        #expect(try reader.read(after: cursor, file: Self.file, identity: "claude").events.map(\.nodes) == [["d"]])
    }

    @Test("A line with a verb this build does not know is skipped, not fatal")
    func unknownVerbIsSkipped() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let views = ViewLog(home: home)
        try await views.record(view(nodes: ["a"]))
        let handle = try FileHandle(forWritingTo: views.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(
            #"{"covered":1,"file":"/tmp/x.pen","identity":"x","nodes":["z"],"revision":"r","scope":"nodes","time":"2026-10-10T00:00:00.000Z","verb":"stare"}"#
                .utf8 + [0x0A]
        ))
        try handle.close()

        let page = try ViewReader(log: views).read()
        #expect(page.events.map(\.nodes) == [["a"]])
        #expect(page.skippedLines == 1)
    }
}
