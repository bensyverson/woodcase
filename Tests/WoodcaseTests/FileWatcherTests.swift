//
//  FileWatcherTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``FileWatcher`` in the library: every backend reports a write, an atomic replace
/// and — the case the first implementation lost — a delete followed by a recreate, and
/// goes on reporting afterwards.
@Suite(.hangGuard)
struct FileWatcherTests {
    private static let backends: [FileWatcher.Backend] = [.native, .polling]

    /// Collects what a watcher reports so a test can wait on a count instead of a clock.
    private actor Collector {
        private(set) var urls: [URL] = []
        var count: Int {
            urls.count
        }

        func record(_ url: URL) {
            urls.append(url)
        }

        func consume(_ watcher: FileWatcher) -> Task<Void, Never> {
            let stream = watcher.changes
            return Task { for await url in stream {
                self.record(url)
            } }
        }
    }

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Waits until the collector holds more than `baseline` reports.
    private func reported(
        after baseline: Int, _ collector: Collector, _ what: Comment
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            if await collector.count > baseline { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        if await collector.count > baseline { return true }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    @Test("A plain write is reported", arguments: backends)
    func reportsAWrite(backend: FileWatcher.Backend) async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        defer { consumer.cancel() }
        await watcher.watch([file])

        try Data("{\"a\":1}".utf8).write(to: file)
        #expect(await reported(after: 0, collector, "the write"))
        await watcher.stop()
    }

    @Test("A delete then a recreate is reported, and so are later edits", arguments: backends)
    func survivesDeleteThenRecreate(backend: FileWatcher.Backend) async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        defer { consumer.cancel() }
        await watcher.watch([file])

        try FileManager.default.removeItem(at: file)
        guard await reported(after: 0, collector, "the delete") else { return }
        // Let the delete's burst settle so the next report is the recreate's own.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await watcher.watchedCount == 1, "a deleted path stays watched")

        let afterDelete = await collector.count
        try Data("{\"b\":2}".utf8).write(to: file)
        guard await reported(after: afterDelete, collector, "the recreate") else { return }
        try await Task.sleep(for: .milliseconds(300))

        let afterRecreate = await collector.count
        try Data("{\"c\":3}".utf8).write(to: file)
        #expect(await reported(after: afterRecreate, collector, "an edit after the recreate"))
        await watcher.stop()
    }

    @Test("An atomic replace, then another edit, is reported", arguments: backends)
    func survivesAtomicReplace(backend: FileWatcher.Backend) async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        defer { consumer.cancel() }
        await watcher.watch([file])

        let temporary = directory.appendingPathComponent(".a.pen.tmp")
        try Data("{\"r\":1}".utf8).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        guard await reported(after: 0, collector, "the replace") else { return }
        try await Task.sleep(for: .milliseconds(300))

        let baseline = await collector.count
        try Data("{\"r\":2}".utf8).write(to: file)
        #expect(await reported(after: baseline, collector, "the edit after the replace"))
        await watcher.stop()
    }

    @Test("A file in a directory that does not exist is not watched", arguments: backends)
    func ignoresAnUnwatchablePath(backend: FileWatcher.Backend) async {
        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        await watcher.watch([URL(fileURLWithPath: "/nowhere/missing.pen")])
        #expect(await watcher.watchedCount == 0)
        await watcher.stop()
    }

    @Test("A path that does not exist yet is watched and reported when it appears", arguments: backends)
    func watchesAPathBeforeItExists(backend: FileWatcher.Backend) async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("later.pen")

        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        defer { consumer.cancel() }
        await watcher.watch([file])
        #expect(await watcher.watchedCount == 1)

        try Data("{}".utf8).write(to: file)
        #expect(await reported(after: 0, collector, "the file appearing"))
        await watcher.stop()
    }

    @Test("Stopping finishes the stream", arguments: backends)
    func stopEndsTheStream(backend: FileWatcher.Backend) async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        let stream = watcher.changes
        await watcher.watch([file])
        let finished = Task {
            for await _ in stream {}
            return true
        }
        await watcher.stop()
        #expect(await finished.value)
    }

    @Test("drain returns the settled reports without a stream", arguments: backends)
    func drainReturnsReports(backend: FileWatcher.Backend) async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let watcher = FileWatcher(debounce: .milliseconds(50), backend: backend)
        await watcher.watch([file])
        try Data("{\"d\":1}".utf8).write(to: file)

        let deadline = ContinuousClock.now + .seconds(60)
        var drained: [URL] = []
        while drained.isEmpty, ContinuousClock.now < deadline {
            drained = await watcher.drain()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(drained.map(\.lastPathComponent) == ["a.pen"])
        #expect(await watcher.drain().isEmpty)
        await watcher.stop()
    }
}
