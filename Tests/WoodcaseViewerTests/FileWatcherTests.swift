//
//  FileWatcherTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

@Suite(.hangGuard)
struct FileWatcherTests {
    /// Collects the changes a watcher reports, so a test can wait on a count rather
    /// than on a clock.
    private actor Collector {
        var urls: [URL] = []
        var count: Int {
            urls.count
        }

        func record(_ url: URL) {
            urls.append(url)
        }

        func consume(_ watcher: FileWatcher) async -> Task<Void, Never> {
            let stream = watcher.changes
            return Task { for await url in stream {
                await self.record(url)
            } }
        }
    }

    @Test("A plain write to a watched file is reported")
    func reportsAWrite() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)

        let watcher = FileWatcher(debounce: .milliseconds(50))
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        await watcher.watch([file])
        defer {
            consumer.cancel()
            Task { await watcher.stop() }
        }

        try Data("{\"version\":\"2.17\",\"children\":[]}".utf8).write(to: file)
        // The name is only worth asserting if something was reported at all; without the
        // guard one late report fails twice and reads like two separate problems.
        guard await waitUntil("the write to be reported", { await collector.count >= 1 }) else { return }
        #expect(await collector.urls.first?.lastPathComponent == "batch.pen")
    }

    @Test("An atomic replace — a temp file renamed over the original — is reported too")
    func survivesAtomicReplace() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)

        let watcher = FileWatcher(debounce: .milliseconds(50))
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        await watcher.watch([file])
        defer {
            consumer.cancel()
            Task { await watcher.stop() }
        }

        // Exactly how PenFileTransaction commits: write a neighbour, then rename over.
        let temporary = scratch.appendingPathComponent(".batch.pen.tmp")
        try Data("{\"version\":\"2.17\",\"children\":[]}".utf8).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)

        await waitUntil("the replace to be reported") { await collector.count >= 1 }
    }

    @Test("The watcher re-arms, so a second edit after a replace is reported as well")
    func reArmsAfterAReplace() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)

        let watcher = FileWatcher(debounce: .milliseconds(50))
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        await watcher.watch([file])
        defer {
            consumer.cancel()
            Task { await watcher.stop() }
        }

        let temporary = scratch.appendingPathComponent(".batch.pen.tmp")
        try Data("{\"version\":\"2.17\",\"children\":[]}".utf8).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        guard await waitUntil("the first change", { await collector.count >= 1 }) else { return }

        try Data("{\"version\":\"2.17\",\"children\":[],\"variables\":{}}".utf8).write(to: file)
        await waitUntil("the second change, proving the watcher re-armed") {
            await collector.count >= 2
        }
    }

    @Test("A file edited through a transaction reaches the watcher")
    func reportsATransaction() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)

        let watcher = FileWatcher(debounce: .milliseconds(50))
        let collector = Collector()
        let consumer = await collector.consume(watcher)
        await watcher.watch([file])
        defer {
            consumer.cancel()
            Task { await watcher.stop() }
        }

        try await PenFileTransaction.run(at: file, identity: "tester", log: ActivityLog(home: scratch), timeout: ViewerFixtures.lockBudget) { document, recorder in
            let node = try #require(document.nodes["Ttl01"])
            var common = node.common
            common.name = "Retitled"
            try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Ttl01", common: common)))
        }

        await waitUntil("the transaction's write to be reported") { await collector.count >= 1 }
    }

    @Test("Stopping the watcher ends the stream, so nothing outlives the server")
    func stopEndsTheStream() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)

        let watcher = FileWatcher(debounce: .milliseconds(50))
        let stream = watcher.changes
        await watcher.watch([file])

        let finished = Task {
            for await _ in stream {}
            return true
        }
        await watcher.stop()
        #expect(await finished.value)
    }

    @Test("A file that does not exist is not watched and does not throw")
    func ignoresAMissingFile() async {
        let watcher = FileWatcher(debounce: .milliseconds(50))
        await watcher.watch([URL(fileURLWithPath: "/nowhere/missing.pen")])
        #expect(await watcher.watchedCount == 0)
        await watcher.stop()
    }
}
