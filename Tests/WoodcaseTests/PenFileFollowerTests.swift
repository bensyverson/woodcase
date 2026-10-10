//
//  PenFileFollowerTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

/// Pins ``PenFileFollower`` against plain file writes and hand-written log rows: a
/// change and its row arrive as one attributed ``PenFileFollower/FileChange``, history
/// arrives as activity, a delete-then-recreate keeps the file followed, and canceling
/// the consumer leaves nothing running. The binary-driven contract lives in
/// `PenFileFollowerContractTests`.
@Suite(.hangGuard)
struct PenFileFollowerTests {
    /// A scratch directory with a .pen file and a log of its own.
    private struct Scratch {
        let directory: URL
        let file: URL
        let log: ActivityLog

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PenFileFollowerTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("design.pen")
            log = ActivityLog(home: directory.appendingPathComponent(".woodcase", isDirectory: true))
            try Data(#"{"version":"2.20","children":[]}"#.utf8).write(to: file)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        /// What a woodcase write does: replace the file, then log the row.
        func write(as identity: String, nodes: [String], revision: String) async throws {
            try Data(#"{"version":"2.20","children":[],"r":"\#(revision)"}"#.utf8).write(to: file, options: .atomic)
            try await log.append([row(identity, nodes: nodes, revision: revision)])
        }

        func row(_ identity: String, nodes: [String], revision: String) -> ActivityEvent {
            ActivityEvent(time: Date(), identity: identity, file: file, op: .set, nodes: nodes, revision: revision)
        }

        /// A write by a tool that does not log.
        func writeUnlogged(_ text: String) throws {
            try Data(text.utf8).write(to: file, options: .atomic)
        }
    }

    @Test("A logged write arrives as one attributed change carrying the row")
    func loggedWriteIsAttributed() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log, matchWindow: .seconds(60)))
        defer { recorder.cancel() }

        try await scratch.write(as: "claude", nodes: ["jSUCH"], revision: "r1")

        let event = await recorder.next("the attributed change") { $0.change?.isAttributed == true }
        #expect(event?.change?.events.map(\.identity) == ["claude"])
        #expect(event?.change?.nodes == ["jSUCH"])
        #expect(event?.change?.revision == "r1")
    }

    @Test("A write made after the follower was created but before it was first polled is not lost")
    func writeBeforeFirstPollIsSeen() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let follower = PenFileFollower(file: scratch.file, log: scratch.log, matchWindow: .seconds(60))
        try await scratch.write(as: "claude", nodes: ["jSUCH"], revision: "r1")

        let recorder = FollowerRecorder(follower)
        defer { recorder.cancel() }
        let event = await recorder.next("the attributed change") { $0.change != nil }
        #expect(event?.change?.events.map(\.revision) == ["r1"])
    }

    @Test("Following from the beginning replays the log as activity, not as changes")
    func beginningReplaysHistoryAsActivity() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try await scratch.log.append([
            scratch.row("ana", nodes: ["a"], revision: "r1"),
            scratch.row("claude", nodes: ["b"], revision: "r2"),
        ])

        let recorder = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log, from: .beginning))
        defer { recorder.cancel() }
        let first = await recorder.next("the first row") { $0.activity != nil }
        let second = await recorder.next("the second row") { $0.activity != nil }
        #expect(first?.activity?.identity == "ana")
        #expect(second?.activity?.identity == "claude")
        #expect(await recorder.received.allSatisfy { $0.change == nil })
    }

    @Test("A row whose write the follower never saw is released as activity after the window")
    func unmatchedRowBecomesActivity() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(PenFileFollower(
            file: scratch.file, log: scratch.log, matchWindow: .milliseconds(200)
        ))
        defer { recorder.cancel() }

        try await scratch.log.append([scratch.row("claude", nodes: ["a"], revision: "r1")])

        let event = await recorder.next("the released row") { $0.activity != nil }
        #expect(event?.activity?.revision == "r1")
    }

    @Test("A write nobody logs arrives unattributed once the window passes")
    func unloggedWriteIsUnattributed() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(PenFileFollower(
            file: scratch.file, log: scratch.log, matchWindow: .milliseconds(200)
        ))
        defer { recorder.cancel() }

        try scratch.writeUnlogged(#"{"version":"2.20","children":[],"x":1}"#)

        let event = await recorder.next("the unattributed change") { $0.change != nil }
        #expect(event?.change?.isAttributed == false)
        #expect(event?.change?.revision == nil)
    }

    @Test(
        "A delete then a recreate keeps the file followed, and later writes still arrive",
        arguments: FileWatcher.Backend.allCases
    )
    func survivesDeleteThenRecreate(backend: FileWatcher.Backend) async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(PenFileFollower(
            file: scratch.file, log: scratch.log, matchWindow: .seconds(60), backend: backend
        ))
        defer { recorder.cancel() }

        try await scratch.write(as: "claude", nodes: ["a"], revision: "r1")
        _ = await recorder.next("the first write") { $0.change?.revision == "r1" }

        try FileManager.default.removeItem(at: scratch.file)
        try await Task.sleep(for: .milliseconds(150))
        try await scratch.write(as: "claude", nodes: ["b"], revision: "r2")
        _ = await recorder.next("the recreate") { $0.change?.revision == "r2" }

        try await scratch.write(as: "claude", nodes: ["c"], revision: "r3")
        let later = await recorder.next("a write after the recreate") { $0.change?.revision == "r3" }
        #expect(later?.change?.nodes == ["c"])
    }

    @Test("The iterator's position resumes a later follower after the last event it took")
    func positionResumes() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try await scratch.log.append([scratch.row("ana", nodes: ["a"], revision: "r1")])

        var iterator = PenFileFollower(file: scratch.file, log: scratch.log, from: .beginning).makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.activity?.revision == "r1")
        let position = iterator.position

        try await scratch.log.append([scratch.row("ana", nodes: ["b"], revision: "r2")])
        let recorder = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log, from: .position(position)))
        defer { recorder.cancel() }
        let resumed = await recorder.next("the row after the position") { $0.activity != nil }
        #expect(resumed?.activity?.revision == "r2")
    }

    @Test("A recorded read arrives as a view with its nodes and revision")
    func readArrivesAsView() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log))
        defer { recorder.cancel() }

        try await ViewLog(beside: scratch.log).record(ViewEvent(
            identity: "claude", file: scratch.file, verb: .get, revision: "r1", nodes: ["jSUCH"]
        ))

        let event = await recorder.next("the view") { $0.view != nil }
        #expect(event?.view?.identity == "claude")
        #expect(event?.view?.nodes == ["jSUCH"])
        #expect(event?.view?.revision == "r1")
    }

    @Test("Views of another file in the same log are not delivered")
    func otherFilesViewsAreFiltered() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let recorder = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log))
        defer { recorder.cancel() }
        let views = ViewLog(beside: scratch.log)

        try await views.record(ViewEvent(
            identity: "claude", file: scratch.directory.appendingPathComponent("other.pen"),
            verb: .get, revision: "r1", nodes: ["other"]
        ))
        try await views.record(ViewEvent(identity: "claude", file: scratch.file, verb: .tree, revision: "r1", nodes: ["mine"]))

        let event = await recorder.next("the view of the followed file") { $0.view != nil }
        #expect(event?.view?.nodes == ["mine"])
        #expect(await recorder.received.compactMap(\.view).count == 1)
    }

    @Test("Following from the beginning replays views, and the position resumes after them")
    func beginningReplaysViews() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let views = ViewLog(beside: scratch.log)
        try await views.record(ViewEvent(identity: "claude", file: scratch.file, verb: .get, revision: "r1", nodes: ["a"]))

        var iterator = PenFileFollower(file: scratch.file, log: scratch.log, from: .beginning).makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.view?.nodes == ["a"])
        let position = iterator.position

        try await views.record(ViewEvent(identity: "claude", file: scratch.file, verb: .get, revision: "r2", nodes: ["b"]))
        let recorder = FollowerRecorder(PenFileFollower(file: scratch.file, log: scratch.log, from: .position(position)))
        defer { recorder.cancel() }
        let resumed = await recorder.next("the view after the position") { $0.view != nil }
        #expect(resumed?.view?.nodes == ["b"])
    }

    @Test("A folder the native watcher cannot open is followed by polling instead")
    func unreadableFolderFallsBackToPolling() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        // Write and search but no read: the event-only open of the folder is refused,
        // while the file itself stays reachable — the shape of a sandbox grant on a
        // single file.
        let folder = scratch.directory.appendingPathComponent("granted", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("design.pen")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        let recorder = FollowerRecorder(PenFileFollower(file: file, log: scratch.log, matchWindow: .milliseconds(200)))
        defer { recorder.cancel() }
        try await Task.sleep(for: .milliseconds(300))
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data(" ".utf8))
        try handle.close()

        let event = await recorder.next("the change seen by polling") { $0.change != nil }
        #expect(event?.change?.isAttributed == false)
    }

    @Test("A row half-written when the follower is made arrives whole once it is finished")
    func halfWrittenRowAtTheEndArrivesWhole() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try await scratch.log.append([scratch.row("ana", nodes: ["a"], revision: "r1")])
        var second = try scratch.row("ana", nodes: ["b"], revision: "r2").jsonLine()
        second.append(JSONLinesFile.newline)
        let handle = try FileHandle(forWritingTo: scratch.log.fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: second.prefix(20))

        let recorder = FollowerRecorder(PenFileFollower(
            file: scratch.file, log: scratch.log, matchWindow: .milliseconds(200)
        ))
        defer { recorder.cancel() }
        try handle.write(contentsOf: second.dropFirst(20))

        let event = await recorder.next("the finished row") { $0.activity != nil }
        #expect(event?.activity?.revision == "r2")
    }

    @Test("Canceling the consuming task ends it and releases the watcher")
    func cancelingReleasesEverything() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let probe = WatcherProbe()
        let follower = PenFileFollower(file: scratch.file, log: scratch.log, matchWindow: .seconds(60))
        let task = Task {
            var iterator = follower.makeAsyncIterator()
            iterator.watcherCreated = { probe.hold($0) }
            while await iterator.next() != nil {}
        }

        // Prove the watch is live before canceling: a write is reported.
        try await scratch.write(as: "claude", nodes: ["a"], revision: "r1")
        let deadline = ContinuousClock.now + .seconds(60)
        while !probe.wasCreated, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(probe.wasCreated)

        task.cancel()
        await task.value

        while probe.isAlive, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!probe.isAlive, "the watcher outlived the canceled follower")
    }

    /// Holds a weak reference to the watcher a follower made.
    private final class WatcherProbe: Sendable {
        private let state = Mutex<(made: Bool, watcher: WeakWatcher)>((false, WeakWatcher()))

        func hold(_ watcher: FileWatcher) {
            state.withLock { $0 = (true, WeakWatcher(watcher)) }
        }

        var wasCreated: Bool {
            state.withLock(\.made)
        }

        var isAlive: Bool {
            state.withLock { $0.watcher.value != nil }
        }
    }

    private struct WeakWatcher {
        weak var value: FileWatcher?
        init(_ value: FileWatcher? = nil) {
            self.value = value
        }
    }
}
