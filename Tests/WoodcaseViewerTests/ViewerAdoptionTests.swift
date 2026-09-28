//
//  ViewerAdoptionTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// A bare `woodcase serve` follows the activity log, and a file first named *after*
/// startup is exactly the case the dashboard exists for: an agent runs `woodcase new`
/// while the viewer is already open.
///
/// Serialized for the same reason ``ViewerPagesTests`` is: every case here binds a
/// socket and warms a render.
@Suite(.serialized, .hangGuard)
struct ViewerAdoptionTests {
    /// An SSE client that keeps what it was written.
    private actor Recorder: SSEWriter {
        private(set) var writes: [String] = []

        func write(_ text: String) async -> Bool {
            writes.append(text)
            return true
        }

        func close() async {}

        func changes() -> [ViewerChange] {
            writes.compactMap { text in
                guard text.contains("event: \(SSEEvent.Name.change.rawValue)\n") else { return nil }
                let json = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { $0.hasPrefix("data: ") }
                    .map { $0.dropFirst("data: ".count) }
                    .joined(separator: "\n")
                return try? ViewerJSON.decoder.decode(ViewerChange.self, from: Data(json.utf8))
            }
        }
    }

    /// Renames a node, recording the write under an identity.
    private func edit(_ file: URL, log: ActivityLog, as identity: String, to name: String) async throws {
        try await PenFileTransaction.run(
            at: file, identity: identity, log: log, timeout: ViewerFixtures.lockBudget
        ) { _, recorder in
            try recorder.apply(.updateCommon(EditOperation.UpdateCommon(
                nodeID: "Ttl01", common: PenNodeCommon(name: name)
            )))
        }
    }

    @Test("A file the log first names after startup is listed, watched and announced")
    func adoptsAFileFirstSeenAfterStartup() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let log = ActivityLog(home: scratch)
        let server = ViewerServer()
        try await server.start(files: [], port: 0, log: log)
        defer { Task { await server.stop() } }

        let context = try #require(await server.context)
        let recorder = Recorder()
        await context.events.add(recorder)
        #expect(await context.files.files.isEmpty)

        // `woodcase new` plus one edit: the file appears on disk and the log names it.
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        try await edit(file, log: log, as: "ana", to: "First")

        let id = ViewerFile(url: file).id
        await waitUntil("the dashboard to list the new file") {
            await context.files.file(id: id) != nil
        }
        await waitUntil("a change announcing it") {
            await recorder.changes().contains { $0.file == id }
        }

        // Watched, not merely listed: the second write is seen by the watcher alone.
        try await edit(file, log: log, as: "ben", to: "Second")
        await waitUntil("a change for the second write") {
            await recorder.changes().contains { $0.file == id && $0.identity == "ben" }
        }
    }

    @Test("A serve given files explicitly adopts nothing the log names later")
    func namedFilesAreTheWholeList() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let log = ActivityLog(home: scratch)
        let named = try ViewerFixtures.copy("batch.pen", into: scratch)
        let server = ViewerServer()
        try await server.start(files: [named], port: 0, log: log)
        defer { Task { await server.stop() } }

        let context = try #require(await server.context)
        let stranger = scratch.appendingPathComponent("other.pen")
        try FileManager.default.copyItem(at: named, to: stranger)
        try await edit(stranger, log: log, as: "ana", to: "Elsewhere")

        // The log names it; the command line did not, so it stays out. Long enough for
        // the follow poll (100 ms) to have read the line several times over.
        try await Task.sleep(for: .seconds(1))
        #expect(await context.files.file(at: stranger) == nil)
        #expect(await context.files.files.count == 1)
    }
}
