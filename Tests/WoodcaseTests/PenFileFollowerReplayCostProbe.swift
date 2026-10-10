//
//  PenFileFollowerReplayCostProbe.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What it costs a follower to hand over the last ten minutes of a long history — the
/// replay Penumbra runs when it opens a bundle — printed as `PROBE` lines.
///
/// The history is shaped like the one Penumbra measured: 64,001 activity rows of about
/// 580 bytes over four rotated archives and the live file (37 MB), and 4,000 views,
/// spread evenly over a week, so the window holds a few dozen of them. Each start is
/// timed until the window's last event has arrived.
///
/// A measurement, not a check of speed — its figures mean something only beside
/// `uptime` — though it does check that each start delivers exactly the window. It
/// runs only when asked:
///
/// ```sh
/// WOODCASE_FOLLOW_REPLAY_COST=1 swift test --filter PenFileFollowerReplayCostProbe
/// ```
@Suite(.serialized)
struct PenFileFollowerReplayCostProbe {
    /// Whether the probe was asked for.
    static let isEnabled = ProcessInfo.processInfo.environment["WOODCASE_FOLLOW_REPLAY_COST"] != nil

    /// Rows in each of the four archives; the live file holds one more.
    static let rowsPerFile = 12800

    /// How many files the activity history spans: four archives and the live file.
    static let files = 5

    /// Views in the view log.
    static let views = 4000

    /// How far back the history reaches.
    static let span: TimeInterval = 7 * 24 * 3600

    /// The replay window.
    static let window: TimeInterval = 10 * 60

    /// A history on disk, and what its window holds.
    struct History {
        let directory: URL
        let file: URL
        let log: ActivityLog
        let cutoff: Date
        let windowRows: [ActivityEvent]
        let windowViews: [ViewEvent]
        let bytes: Int

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PenFileFollowerReplayCostProbe-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("design.pen")
            self.file = file
            try Data(#"{"version":"2.20","children":[]}"#.utf8).write(to: file)
            let log = ActivityLog(home: directory.appendingPathComponent(".woodcase", isDirectory: true))
            self.log = log

            let now = Date()
            let first = now.addingTimeInterval(-PenFileFollowerReplayCostProbe.span)
            let cutoff = now.addingTimeInterval(-PenFileFollowerReplayCostProbe.window)
            self.cutoff = cutoff
            let total = PenFileFollowerReplayCostProbe.rowsPerFile * PenFileFollowerReplayCostProbe.files + 1
            let step = PenFileFollowerReplayCostProbe.span / Double(total)
            let padding = String(repeating: "x", count: 110)
            var rows: [ActivityEvent] = []
            rows.reserveCapacity(total)
            for index in 0 ..< total {
                rows.append(ActivityEvent(
                    time: first.addingTimeInterval(step * Double(index)),
                    identity: index % 3 == 0 ? "claude" : "ana",
                    file: file,
                    op: .set,
                    nodes: ["n\(index)", "card-\(index % 97)"],
                    paths: ["page/section-\(index % 7)/\(padding)", "page/card-\(index % 97)/\(padding)", padding],
                    revision: String(format: "%016x", index)
                ))
            }
            var chunks: [[ActivityEvent]] = []
            var start = 0
            for index in 0 ..< PenFileFollowerReplayCostProbe.files {
                let count = PenFileFollowerReplayCostProbe.rowsPerFile + (index == PenFileFollowerReplayCostProbe.files - 1 ? 1 : 0)
                chunks.append(Array(rows[start ..< start + count]))
                start += count
            }
            try FollowHistory.write(chunks, to: log)

            let viewStep = PenFileFollowerReplayCostProbe.span / Double(PenFileFollowerReplayCostProbe.views)
            let views = (0 ..< PenFileFollowerReplayCostProbe.views).map { index in
                ViewEvent(
                    time: first.addingTimeInterval(viewStep * Double(index) + viewStep / 2),
                    identity: "claude", file: file, verb: .get, revision: "v\(index)", nodes: ["n\(index)"]
                )
            }
            try FollowHistory.write([views], to: ViewLog(beside: log))

            windowRows = rows.filter { $0.time >= cutoff }
            windowViews = views.filter { $0.time >= cutoff }
            let names = try FileManager.default.contentsOfDirectory(atPath: log.home.path)
            bytes = try names.reduce(0) { sum, name in
                let attributes = try FileManager.default.attributesOfItem(atPath: log.home.appendingPathComponent(name).path)
                return sum + ((attributes[.size] as? Int) ?? 0)
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Follows from `start` until the window's last event arrives, keeping only the
    /// window's events.
    ///
    /// - Returns: The window's rows and views as delivered, how many older events came
    ///   with them, and how long they took.
    static func replay(
        _ history: History,
        from start: PenFileFollower.Start
    ) async -> (rows: [ActivityEvent], views: [ViewEvent], older: Int, elapsed: Duration) {
        let expected = history.windowRows.count + history.windowViews.count
        var rows: [ActivityEvent] = []
        var views: [ViewEvent] = []
        var older = 0
        let clock = ContinuousClock()
        let began = clock.now
        var iterator = PenFileFollower(file: history.file, log: history.log, from: start).makeAsyncIterator()
        while rows.count + views.count < expected, let event = await iterator.next() {
            if let row = event.activity {
                if row.time >= history.cutoff { rows.append(row) } else { older += 1 }
            }
            if let view = event.view {
                if view.time >= history.cutoff { views.append(view) } else { older += 1 }
            }
        }
        return (rows, views, older, clock.now - began)
    }

    /// Seconds in a duration.
    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    @Test("Replaying the last ten minutes of a 64,001-row history", .enabled(if: isEnabled))
    func probe() async throws {
        let history = try History()
        defer { history.remove() }
        print("PROBE history \(history.bytes) bytes, window \(history.windowRows.count) rows \(history.windowViews.count) views")

        let beginning = await Self.replay(history, from: .beginning)
        print(String(format: "PROBE .beginning, dropping older: %.3f s", Self.seconds(beginning.elapsed)))
        #expect(beginning.rows == history.windowRows)
        #expect(beginning.views == history.windowViews)

        let since = await Self.replay(history, from: .since(history.cutoff))
        print(String(format: "PROBE .since(cutoff): %.3f s", Self.seconds(since.elapsed)))
        #expect(since.older == 0, "a .since follower delivered events from before its date")
        #expect(since.rows == history.windowRows)
        #expect(since.views == history.windowViews)
    }
}
