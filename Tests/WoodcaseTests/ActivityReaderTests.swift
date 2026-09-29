//
//  ActivityReaderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises ``ActivityReader``: resuming from an offset, filtering, and what
/// happens to a follower when the log rotates or a writer is mid-append.
@Suite(.hangGuard)
struct ActivityReaderTests {
    // MARK: - Helpers

    private func withTemporaryHome<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityReaderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    private static let demo = URL(fileURLWithPath: "/Users/agent/Designs/demo.pen")
    private static let other = URL(fileURLWithPath: "/Users/agent/Designs/other.pen")

    private static func event(
        identity: String = "logger",
        file: URL = demo,
        revision: String
    ) -> ActivityEvent {
        ActivityEvent(
            time: Date(),
            identity: identity,
            file: file,
            op: .set,
            nodes: ["jSUCH"],
            paths: ["layout-vertical/child-1"],
            revision: revision
        )
    }

    // MARK: - Resuming

    @Test("A reader resumes from its offset without re-reading what it saw")
    func readResumesFromAnOffsetWithoutRereading() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event(revision: "r1"), Self.event(revision: "r2")])

            let first = try reader.read()
            #expect(first.events.map(\.revision) == ["r1", "r2"])
            #expect(first.restarted == false)
            #expect(first.nextOffset > 0)

            let empty = try reader.read(from: first.nextOffset)
            #expect(empty.events.isEmpty)
            #expect(empty.nextOffset == first.nextOffset)

            try await log.append([Self.event(revision: "r3")])
            let resumed = try reader.read(from: first.nextOffset)
            #expect(resumed.events.map(\.revision) == ["r3"])
            #expect(resumed.nextOffset > first.nextOffset)
        }
    }

    @Test("Reading a log that does not exist yet is empty, not an error")
    func readingAMissingLogIsEmpty() async throws {
        try await withTemporaryHome { home in
            let page = try ActivityReader(log: ActivityLog(home: home)).read()
            #expect(page.events.isEmpty)
            #expect(page.nextOffset == 0)
        }
    }

    @Test("A partial trailing line is left for the next read")
    func partialTrailingLineIsNotConsumed() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event(revision: "r1")])

            // A writer caught mid-append: a complete line, then half of the next.
            let handle = try FileHandle(forWritingTo: log.fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(#"{"identity":"logger","op":"se"#.utf8))
            try handle.close()

            let page = try reader.read()
            #expect(page.events.map(\.revision) == ["r1"])
            #expect(page.skippedLines == 0)

            // Completing the line makes it readable from the same offset.
            let rest = try Self.event(revision: "r2").jsonLine()
            let finish = try FileHandle(forWritingTo: log.fileURL)
            try finish.seek(toOffset: page.nextOffset)
            try finish.write(contentsOf: rest + Data([0x0A]))
            try finish.close()

            let second = try reader.read(from: page.nextOffset)
            #expect(second.events.map(\.revision) == ["r2"])
        }
    }

    @Test("An undecodable line is skipped and counted rather than wedging the reader")
    func undecodableLineIsSkipped() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1")])
            let handle = try FileHandle(forWritingTo: log.fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("not json\n".utf8))
            try handle.close()
            try await log.append([Self.event(revision: "r2")])

            let page = try ActivityReader(log: log).read()
            #expect(page.events.map(\.revision) == ["r1", "r2"])
            #expect(page.skippedLines == 1)
        }
    }

    // MARK: - Filtering

    @Test("The identity filter selects one writer's events")
    func identityFilterSelectsOneWriter() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([
                Self.event(identity: "ana", revision: "r1"),
                Self.event(identity: "bo", revision: "r2"),
                Self.event(identity: "ana", revision: "r3"),
            ])

            let page = try ActivityReader(log: log).read(identity: "ana")
            #expect(page.events.map(\.revision) == ["r1", "r3"])
        }
    }

    @Test("The file filter selects one document's events, and the offset still covers all of them")
    func fileFilterSelectsOneDocument() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([
                Self.event(file: Self.demo, revision: "r1"),
                Self.event(file: Self.other, revision: "r2"),
            ])

            let filtered = try reader.read(file: Self.demo)
            let unfiltered = try reader.read()
            #expect(filtered.events.map(\.revision) == ["r1"])
            #expect(filtered.nextOffset == unfiltered.nextOffset)
        }
    }

    // MARK: - Rotation

    @Test("A rotated log restarts the follower from zero and says so")
    func rotationIsFlaggedAsARestart() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event(revision: "r1"), Self.event(revision: "r2")])
            let before = try reader.read()

            // Rotate by hand: the live file is replaced with a shorter one.
            try FileManager.default.moveItem(
                at: log.fileURL,
                to: home.appendingPathComponent("activity.20260829T000000Z.jsonl")
            )
            try await log.append([Self.event(revision: "r3")])

            let after = try reader.read(from: before.nextOffset)
            #expect(after.restarted)
            #expect(after.events.map(\.revision) == ["r3"])
        }
    }

    // MARK: - Tail and follow

    @Test("Tail returns the last events in order")
    func tailReturnsTheLastEvents() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append((1 ... 5).map { Self.event(revision: "r\($0)") })
            let last = try ActivityReader(log: log).tail(count: 2)
            #expect(last.map(\.revision) == ["r4", "r5"])
        }
    }

    @Test("Tail honors the filters")
    func tailHonorsFilters() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([
                Self.event(identity: "ana", revision: "r1"),
                Self.event(identity: "bo", revision: "r2"),
                Self.event(identity: "ana", revision: "r3"),
            ])
            let last = try ActivityReader(log: log).tail(count: 1, identity: "ana")
            #expect(last.map(\.revision) == ["r3"])
        }
    }

    /// The first `count` revisions a follow yields, then stops following.
    ///
    /// Every wait on a follow in this suite goes through ``BoundedWait``: the loop
    /// below ends only when the log delivers, so left unbounded it is exactly the
    /// suspended-forever task that stops a whole run without printing anything.
    ///
    /// - Parameters:
    ///   - count: How many events to take.
    ///   - follow: The feed to take them from.
    /// - Returns: The revisions taken, in order.
    private static func revisions(
        _ count: Int,
        from follow: ActivityReader.Follow
    ) async -> [String] {
        var seen: [String] = []
        for await event in follow {
            seen.append(event.revision)
            if seen.count == count { break }
        }
        return seen
    }

    @Test("Follow yields the events already in the log without waiting for a poll")
    func followYieldsExistingEvents() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1"), Self.event(revision: "r2")])

            let follow = ActivityReader(log: log).follow()
            let seen = try await BoundedWait.value { await Self.revisions(2, from: follow) }
            #expect(seen == ["r1", "r2"])
        }
    }

    @Test("Follow yields an event appended after it started")
    func followYieldsLaterEvents() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let follow = ActivityReader(log: log).follow(pollInterval: .milliseconds(10))

            let seen = try await BoundedWait.value { () -> [String] in
                async let taken = Self.revisions(1, from: follow)
                try await log.append([Self.event(revision: "later")])
                return await taken
            }
            #expect(seen == ["later"])
        }
    }

    // MARK: - A follow is a value, not a task

    @Test("A follow starts nothing of its own: two iterations each replay from its offset")
    func followIsAValueNotARunningTask() async throws {
        // The property under test is the whole of why a follow cannot be leaked. A
        // feed backed by its own unstructured task begins polling the moment it is
        // made and stops only when something reaches back to cancel it, so a consumer
        // that is dropped, wedged or simply never written leaves a poll loop running
        // for the life of the process. A feed that is a *value* has nothing to leak:
        // the polling is the consumer's own task, and a second iteration is a second,
        // independent walk from the same offset rather than the leftovers of the first.
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1")])
            let follow = ActivityReader(log: log).follow(pollInterval: .milliseconds(10))

            let first = try await BoundedWait.value { await Self.revisions(1, from: follow) }
            let second = try await BoundedWait.value { await Self.revisions(1, from: follow) }

            #expect(first == ["r1"])
            #expect(second == ["r1"])
        }
    }

    @Test("Canceling the task that is following ends the iteration")
    func cancelingTheConsumerEndsTheFollow() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event(revision: "r1")])
            let follow = ActivityReader(log: log).follow(pollInterval: .milliseconds(10))

            let seen = try await BoundedWait.value { () -> Int in
                let live = AsyncStream<Void>.makeStream()
                let follower = Task { () -> Int in
                    var count = 0
                    for await _ in follow {
                        count += 1
                        live.continuation.finish()
                    }
                    return count
                }
                // Cancel only once the follower is demonstrably iterating, so the
                // assertion is about cancellation and not about a race to start.
                for await _ in live.stream {}
                follower.cancel()
                return await follower.value
            }
            #expect(seen >= 1)
        }
    }
}
