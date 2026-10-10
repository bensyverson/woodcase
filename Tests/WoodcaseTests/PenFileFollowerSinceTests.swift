//
//  PenFileFollowerSinceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenFileFollower/Start/since(_:)``: the rows and views at or after the date
/// arrive as history, wherever they are among the archives, in the shapes and order a
/// ``PenFileFollower/Start/beginning`` follower gives them, and everything written after
/// the follower was made arrives live, exactly as it would for ``PenFileFollower/Start/end``.
@Suite(.hangGuard)
struct PenFileFollowerSinceTests {
    /// A scratch directory with a .pen file and a log of its own.
    private struct Scratch {
        let directory: URL
        let file: URL
        let log: ActivityLog
        let now = Date()

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PenFileFollowerSinceTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("design.pen")
            log = ActivityLog(home: directory.appendingPathComponent(".woodcase", isDirectory: true))
            try Data(#"{"version":"2.20","children":[]}"#.utf8).write(to: file)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        /// `minutes` before now.
        func ago(_ minutes: Double) -> Date {
            now.addingTimeInterval(-minutes * 60)
        }

        /// A row for the followed file.
        func row(_ revision: String, at time: Date, file other: URL? = nil) -> ActivityEvent {
            ActivityEvent(time: time, identity: "claude", file: other ?? file, op: .set, nodes: ["n"], revision: revision)
        }

        /// A view of the followed file.
        func view(_ revision: String, at time: Date) -> ViewEvent {
            ViewEvent(time: time, identity: "ana", file: file, verb: .get, revision: revision, nodes: ["n"])
        }

        /// What a woodcase write does: replace the file, then log the row.
        func write(revision: String) async throws {
            try Data(#"{"version":"2.20","children":[],"r":"\#(revision)"}"#.utf8).write(to: file, options: .atomic)
            try await log.append([row(revision, at: Date())])
        }

        func follower(since date: Date) -> PenFileFollower {
            PenFileFollower(file: file, log: log, from: .since(date), matchWindow: .seconds(60))
        }
    }

    /// Waits until the recorder holds `count` events, then a little longer, so a test
    /// can tell "exactly these" from "these and more on the way".
    private static func settled(_ recorder: FollowerRecorder, count: Int) async -> [PenFileFollower.Event] {
        let deadline = ContinuousClock.now + .seconds(60)
        while await recorder.received.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await Task.sleep(for: .milliseconds(400))
        return await recorder.received
    }

    @Test("Rows at or after the date arrive as activity, and a write made after the follower arrives as a change")
    func windowThenLive() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([[
            scratch.row("r1", at: scratch.ago(30)),
            scratch.row("r2", at: scratch.ago(20)),
            scratch.row("r3", at: scratch.ago(5)),
            scratch.row("r4", at: scratch.ago(1)),
        ]], to: scratch.log)

        let recorder = FollowerRecorder(scratch.follower(since: scratch.ago(10)))
        defer { recorder.cancel() }
        try await scratch.write(revision: "live")
        _ = await recorder.next("the live change") { $0.change?.revision == "live" }

        let received = await recorder.received
        #expect(received.compactMap(\.activity).map(\.revision) == ["r3", "r4"])
        #expect(received.compactMap(\.change).map(\.revision) == ["live"])
        #expect(received.firstIndex { $0.change != nil } == 2)
    }

    @Test("A window that starts inside an archive is read from there, through the later archives and the live file")
    func windowReachesIntoArchives() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([
            [scratch.row("r1", at: scratch.ago(180)), scratch.row("r2", at: scratch.ago(120))],
            [scratch.row("r3", at: scratch.ago(60)), scratch.row("r4", at: scratch.ago(15)), scratch.row("r5", at: scratch.ago(8))],
            [scratch.row("r6", at: scratch.ago(7))],
            [scratch.row("r7", at: scratch.ago(5)), scratch.row("r8", at: scratch.ago(2))],
        ], to: scratch.log)

        let recorder = FollowerRecorder(scratch.follower(since: scratch.ago(10)))
        defer { recorder.cancel() }
        let received = await Self.settled(recorder, count: 4)
        #expect(received.compactMap(\.activity).map(\.revision) == ["r5", "r6", "r7", "r8"])
        #expect(received.count == 4)
    }

    @Test("A window row filed behind a row stamped a moment before the date is delivered")
    func slightlyOutOfOrderRowIsDelivered() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let date = scratch.ago(10)
        try FollowHistory.write([[
            scratch.row("old", at: scratch.ago(60)),
            scratch.row("inside", at: date.addingTimeInterval(0.2)),
            scratch.row("stamped-earlier", at: date.addingTimeInterval(-1)),
            scratch.row("later", at: scratch.ago(2)),
        ]], to: scratch.log)

        let recorder = FollowerRecorder(scratch.follower(since: date))
        defer { recorder.cancel() }
        let received = await Self.settled(recorder, count: 2)
        #expect(received.compactMap(\.activity).map(\.revision) == ["inside", "later"])
    }

    @Test("A row stamped exactly at the date is in the window; one a millisecond earlier is not")
    func dateIsInclusive() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let date = Date(timeIntervalSince1970: (scratch.ago(10).timeIntervalSince1970 * 1000).rounded() / 1000)
        try FollowHistory.write([[
            scratch.row("before", at: date.addingTimeInterval(-0.001)),
            scratch.row("at", at: date),
        ]], to: scratch.log)

        let recorder = FollowerRecorder(scratch.follower(since: date))
        defer { recorder.cancel() }
        let received = await Self.settled(recorder, count: 1)
        #expect(received.compactMap(\.activity).map(\.revision) == ["at"])
    }

    @Test("Views at or after the date arrive, older ones do not, and later reads follow")
    func viewsWindowThenLive() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let views = ViewLog(beside: scratch.log)
        try FollowHistory.write([
            [scratch.view("v1", at: scratch.ago(40))],
            [scratch.view("v2", at: scratch.ago(30)), scratch.view("v3", at: scratch.ago(5))],
        ], to: views)

        let recorder = FollowerRecorder(scratch.follower(since: scratch.ago(10)))
        defer { recorder.cancel() }
        try await views.record(scratch.view("v4", at: Date()))
        let received = await Self.settled(recorder, count: 2)
        #expect(received.compactMap(\.view).map(\.revision) == ["v3", "v4"])
        #expect(received.count == 2)
    }

    @Test("A date after every row delivers no history, and live writes still arrive as changes")
    func futureDateDeliversOnlyLive() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([[scratch.row("r1", at: scratch.ago(5))]], to: scratch.log)
        try FollowHistory.write([[scratch.view("v1", at: scratch.ago(5))]], to: ViewLog(beside: scratch.log))

        let recorder = FollowerRecorder(scratch.follower(since: scratch.now.addingTimeInterval(3600)))
        defer { recorder.cancel() }
        try await scratch.write(revision: "live")
        _ = await recorder.next("the live change") { $0.change?.revision == "live" }
        #expect(await recorder.received.count == 1)
    }

    @Test("With no log yet, the first write arrives as an attributed change")
    func noLogYet() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(scratch.follower(since: scratch.ago(10)))
        defer { recorder.cancel() }
        try await scratch.write(revision: "live")
        let change = await recorder.next("the live change") { $0.change != nil }
        #expect(change?.change?.isAttributed == true)
        #expect(await recorder.received.count == 1)
    }

    @Test("The window arrives exactly as a follower from the beginning gives it, older events dropped")
    func matchesBeginningFiltered() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let other = scratch.directory.appendingPathComponent("other.pen")
        var files: [[ActivityEvent]] = []
        var minute = 200.0
        for file in 0 ..< 4 {
            var rows: [ActivityEvent] = []
            for index in 0 ..< 6 {
                minute -= 7
                rows.append(scratch.row("f\(file)-\(index)", at: scratch.ago(minute), file: index == 2 ? other : nil))
            }
            files.append(rows)
        }
        try FollowHistory.write(files, to: scratch.log)
        try FollowHistory.write([
            (0 ..< 5).map { scratch.view("a\($0)", at: scratch.ago(190 - Double($0) * 30)) },
            (0 ..< 5).map { scratch.view("b\($0)", at: scratch.ago(40 - Double($0) * 8)) },
        ], to: ViewLog(beside: scratch.log))
        let cutoff = scratch.ago(60)

        let all = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log, from: .beginning))
        defer { all.cancel() }
        let beginning = await Self.settled(all, count: 20 + 10)
        let expected = beginning.filter { event in
            (event.activity?.time ?? event.view?.time).map { $0 >= cutoff } ?? true
        }
        #expect(expected.count < beginning.count)

        let window = FollowerRecorder(scratch.follower(since: cutoff))
        defer { window.cancel() }
        #expect(await Self.settled(window, count: expected.count) == expected)
    }
}
