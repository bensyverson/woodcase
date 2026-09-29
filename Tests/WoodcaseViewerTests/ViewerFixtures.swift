//
//  ViewerFixtures.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Shared scaffolding: the .pen fixtures, a scratch directory per test, and a
/// ready-made ``ViewerContext``.
///
/// The fixtures are the ones `WoodcaseTests` already keeps — one corpus, not two —
/// reached from this file's own path, and always copied into a temporary directory
/// before a test edits them.
enum ViewerFixtures {
    /// The shared fixture directory, `Tests/WoodcaseTests/Fixtures`.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("WoodcaseTests/Fixtures")

    /// A fresh temporary directory, removed when the returned handle is discarded.
    static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-viewer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies a named fixture into `directory` and returns the copy's URL.
    static func copy(_ name: String, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(
            at: self.directory.appendingPathComponent(name), to: destination
        )
        return destination
    }

    /// How long a viewer test waits for a .pen file's lock before calling it a failure.
    ///
    /// The product default is five seconds, which is the right answer for a person at
    /// a terminal and the wrong one inside this suite. A viewer test's own server, the
    /// transaction it is waiting on, and every ``EditableDocument`` the rest of the
    /// suite is building all queue on the **main actor**; while a heavy library suite
    /// holds it — a 5000-node layout, a WebKit round trip — this test's lock poll does
    /// not run at all, and a budget it cannot poll against measures the machine rather
    /// than the lock. Bounded at "not hung" scale instead, per `project/gotchas.md`.
    static let lockBudget: Duration = .seconds(60)

    /// How long a viewer test waits for its own loopback server to answer.
    ///
    /// Same reasoning as ``lockBudget``: the server being waited on is in *this*
    /// process, behind the same main actor as whatever else the suite is running.
    static let requestBudget: TimeInterval = 60

    /// How long ``waitUntil(_:within:poll:_:)`` polls before calling a condition failed.
    ///
    /// The same reasoning as ``lockBudget``, and the same number on purpose. The path a
    /// viewer test waits on is several cooperative hops long — a Dispatch source, an
    /// actor, a debounce sleep, a stream, a collector — and this suite has been measured
    /// resuming a 10 ms `Task.sleep` twelve seconds late. Four hops of that overruns
    /// anything set at the scale of the behavior, so the bound is set at the scale of
    /// "this is hung" instead.
    static let waitBudget: Duration = .seconds(60)

    /// A context over the given files, logging into `home`.
    static func context(files: [URL], home: URL) -> ViewerContext {
        ViewerContext(
            files: ViewerFileIndex(files: files),
            renders: ViewerFixtures.renders(),
            log: ActivityLog(home: home),
            events: SSEHub()
        )
    }
}

/// Waits for a condition to hold, and records an issue naming it if it never does.
///
/// Bounds are deliberately generous: the suite runs concurrently, and a bound near the
/// interval under test measures machine load rather than behavior. See
/// ``ViewerFixtures/waitBudget``.
///
/// The evaluation *after* the deadline is the point of this shape rather than a tidier
/// loop. Under the parallel suite the poll's real granularity is nothing like `poll` —
/// a 10 ms `Task.sleep` has been measured resuming twelve seconds later — so a loop that
/// only ever tests the condition while inside the deadline can sleep straight past the
/// moment it came true and record a timeout that nothing earned, naming the watcher or
/// the hub rather than the wait. One last look costs nothing and closes that whole class
/// of false failure.
///
/// - Parameters:
///   - description: What is being waited for, as it should read in a failure.
///   - bound: How long to keep polling before the final evaluation. Defaults to
///     ``ViewerFixtures/waitBudget``.
///   - poll: How long to suspend between attempts.
///   - condition: The state being waited for.
/// - Returns: Whether the condition held, so a caller can skip the assertions that
///   would only restate the same failure.
@discardableResult
func waitUntil(
    _ description: Comment,
    within bound: Duration = ViewerFixtures.waitBudget,
    poll: Duration = .milliseconds(50),
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + bound
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: poll)
    }
    if await condition() { return true }
    Issue.record("timed out waiting for \(description) after \(bound)")
    return false
}
