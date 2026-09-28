//
//  ViewerMultipleLogsTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The viewer over more than one activity log.
///
/// `woodcase serve a.pen b.pen` resolves a log per file, and two files in different
/// projects have different logs. Everything the viewer reads from the log — the adopted
/// file list, a file's feed, presence — has to see all of them, and see each of them once.
@Suite("The viewer over several logs", .hangGuard)
struct ViewerMultipleLogsTests {
    /// An event for `file`, at `time`.
    private static func event(
        _ file: URL, identity: String, at time: Date = Date(), revision: String = "r1"
    ) -> ActivityEvent {
        ActivityEvent(time: time, identity: identity, file: file, op: .set, revision: revision)
    }

    @Test("With no files given, the index adopts from every log it was handed")
    func adoptsFromEveryLog() async throws {
        let left = try ViewerFixtures.scratch()
        let right = try ViewerFixtures.scratch()
        defer {
            try? FileManager.default.removeItem(at: left)
            try? FileManager.default.removeItem(at: right)
        }
        let first = try ViewerFixtures.copy("batch.pen", into: left)
        let second = try ViewerFixtures.copy("addressing.pen", into: right)
        let leftLog = ActivityLog(home: left)
        let rightLog = ActivityLog(home: right)
        try await leftLog.append([Self.event(first, identity: "ana")])
        try await rightLog.append([Self.event(second, identity: "bo")])

        let index = ViewerFileIndex(files: [])
        await index.adoptFilesFromLogs([leftLog, rightLog])

        #expect(await Set(index.files.map(\.name)) == ["batch", "addressing"])
    }

    @Test("One log handed over twice adopts its files once")
    func duplicateLogsAreReadOnce() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let log = ActivityLog(home: scratch)
        try await log.append([Self.event(file, identity: "ana")])

        let index = ViewerFileIndex(files: [])
        await index.adoptFilesFromLogs([log, log])

        #expect(await index.files.count == 1)
    }

    @Test("A file's feed comes from its own log, whichever of the logs that is")
    func feedReadsTheRightLog() async throws {
        let left = try ViewerFixtures.scratch()
        let right = try ViewerFixtures.scratch()
        defer {
            try? FileManager.default.removeItem(at: left)
            try? FileManager.default.removeItem(at: right)
        }
        let first = try ViewerFixtures.copy("batch.pen", into: left)
        let second = try ViewerFixtures.copy("addressing.pen", into: right)
        try await ActivityLog(home: left).append([Self.event(first, identity: "ana")])
        try await ActivityLog(home: right).append([Self.event(second, identity: "bo")])

        let context = ViewerContext(
            files: ViewerFileIndex(files: [first, second]),
            renders: ViewerFixtures.renders(),
            logs: [ActivityLog(home: left), ActivityLog(home: right)],
            events: SSEHub()
        )

        #expect(PageData.events(context, file: first).map(\.identity) == ["ana"])
        #expect(PageData.events(context, file: second).map(\.identity) == ["bo"])
    }

    @Test("The merged feed is in time order across logs, newest last")
    func mergedFeedIsInTimeOrder() async throws {
        let left = try ViewerFixtures.scratch()
        let right = try ViewerFixtures.scratch()
        defer {
            try? FileManager.default.removeItem(at: left)
            try? FileManager.default.removeItem(at: right)
        }
        let first = try ViewerFixtures.copy("batch.pen", into: left)
        let second = try ViewerFixtures.copy("addressing.pen", into: right)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try await ActivityLog(home: left).append([Self.event(first, identity: "ana", at: start)])
        try await ActivityLog(home: right)
            .append([Self.event(second, identity: "bo", at: start.addingTimeInterval(-60))])

        let context = ViewerContext(
            files: ViewerFileIndex(files: [first, second]),
            renders: ViewerFixtures.renders(),
            logs: [ActivityLog(home: left), ActivityLog(home: right)],
            events: SSEHub()
        )

        #expect(PageData.events(context).map(\.identity) == ["bo", "ana"])
    }

    @Test("Presence folds every log's writers together")
    func presenceCoversEveryLog() async throws {
        let left = try ViewerFixtures.scratch()
        let right = try ViewerFixtures.scratch()
        defer {
            try? FileManager.default.removeItem(at: left)
            try? FileManager.default.removeItem(at: right)
        }
        let first = try ViewerFixtures.copy("batch.pen", into: left)
        let second = try ViewerFixtures.copy("addressing.pen", into: right)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try await ActivityLog(home: left).append([Self.event(first, identity: "ana", at: start)])
        try await ActivityLog(home: right)
            .append([Self.event(second, identity: "bo", at: start.addingTimeInterval(1))])

        let context = ViewerContext(
            files: ViewerFileIndex(files: [first, second]),
            renders: ViewerFixtures.renders(),
            logs: [ActivityLog(home: left), ActivityLog(home: right)],
            events: SSEHub()
        )

        #expect(await PageData.presence(context).map(\.name) == ["ana", "bo"])
    }

    @Test("The header names every log being followed")
    func headerNamesEveryLog() throws {
        let left = try ViewerFixtures.scratch()
        let right = try ViewerFixtures.scratch()
        defer {
            try? FileManager.default.removeItem(at: left)
            try? FileManager.default.removeItem(at: right)
        }
        let context = ViewerContext(
            files: ViewerFileIndex(files: []),
            renders: ViewerFixtures.renders(),
            logs: [ActivityLog(home: left), ActivityLog(home: right)],
            events: SSEHub()
        )

        let path = PageData.logPath(context)
        #expect(path.contains(left.lastPathComponent))
        #expect(path.contains(right.lastPathComponent))
    }
}
