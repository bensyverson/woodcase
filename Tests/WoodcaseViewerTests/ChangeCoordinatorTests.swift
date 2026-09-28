//
//  ChangeCoordinatorTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

@Suite(.hangGuard)
struct ChangeCoordinatorTests {
    /// An SSE client that keeps what it was written.
    private actor Recorder: SSEWriter {
        private(set) var writes: [String] = []

        func write(_ text: String) async -> Bool {
            writes.append(text)
            return true
        }

        func close() async {}

        /// The `data:` payloads of events with a given name, decoded.
        func payloads<T: Decodable>(_ name: SSEEvent.Name, as type: T.Type) -> [T] {
            writes.compactMap { text in
                guard text.contains("event: \(name.rawValue)\n") else { return nil }
                let json = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { $0.hasPrefix("data: ") }
                    .map { $0.dropFirst("data: ".count) }
                    .joined(separator: "\n")
                return try? ViewerJSON.decoder.decode(type, from: Data(json.utf8))
            }
        }
    }

    private struct Bench {
        let scratch: URL
        let file: URL
        let context: ViewerContext
        let recorder: Recorder

        init() async throws {
            scratch = try ViewerFixtures.scratch()
            file = try ViewerFixtures.copy("batch.pen", into: scratch)
            context = ViewerFixtures.context(files: [file], home: scratch)
            recorder = Recorder()
            await context.events.add(recorder)
        }

        func coordinator() -> ChangeCoordinator {
            ChangeCoordinator(
                context: context,
                matchWindow: .milliseconds(300),
                pollInterval: .milliseconds(20)
            )
        }

        func clean() {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    private func event(_ identity: String, file: URL) -> ActivityEvent {
        ActivityEvent(
            time: Date(),
            identity: identity,
            file: file,
            op: .set,
            nodes: ["Ttl01"],
            paths: ["Canvas/Title"],
            revision: "r1"
        )
    }

    @Test("A change carries the file, its revision and the artboards to re-request")
    func publishesAChange() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()

        await coordinator.fileChanged(bench.file)

        let changes = await bench.recorder.payloads(.change, as: ViewerChange.self)
        #expect(changes.count == 1)
        let change = try #require(changes.first)
        #expect(change.file == ViewerFile(url: bench.file).id)
        #expect(change.name == "batch")
        #expect(!change.revision.isEmpty)
        #expect(change.artboards == ["Cnv01", "Brd01", "Cmp01"])
    }

    @Test("A write nobody logged is published unattributed, which is the truth")
    func publishesUnattributed() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()

        await coordinator.fileChanged(bench.file)

        let change = try #require(await bench.recorder.payloads(.change, as: ViewerChange.self).first)
        #expect(change.identity == nil)
        #expect(change.nodes.isEmpty)
        #expect(change.op == nil)
    }

    @Test("A log event already in hand attributes the change it explains")
    func attributesAChange() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()

        await coordinator.logged(event("ana", file: bench.file))
        await coordinator.fileChanged(bench.file)

        let change = try #require(await bench.recorder.payloads(.change, as: ViewerChange.self).first)
        #expect(change.identity == "ana")
        #expect(change.op == .set)
        #expect(change.nodes == ["Ttl01"])
        #expect(change.paths == ["Canvas/Title"])
    }

    @Test("Events are attached once, so the next change is not attributed to the last edit")
    func doesNotReuseEvents() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()

        await coordinator.logged(event("ana", file: bench.file))
        await coordinator.fileChanged(bench.file)
        await coordinator.fileChanged(bench.file)

        let changes = await bench.recorder.payloads(.change, as: ViewerChange.self)
        #expect(changes.count == 2)
        #expect(changes[0].identity == "ana")
        #expect(changes[1].identity == nil)
    }

    @Test("A log event publishes presence and folds into the running tally")
    func publishesPresence() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()

        await coordinator.logged(event("ana", file: bench.file))
        await coordinator.logged(event("ben", file: bench.file))

        let presence = try #require(await bench.recorder.payloads(.presence, as: ViewerPresence.self).last)
        #expect(presence.identities.map(\.name) == ["ana", "ben"])
        #expect(await coordinator.currentPresence.identities.count == 2)
        // The identity's files are named by viewer id, so the page can link them.
        #expect(presence.identities[0].files == [ViewerFile(url: bench.file).id])
    }

    @Test("A change to a file this server does not serve publishes nothing")
    func ignoresUnservedFiles() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()

        await coordinator.fileChanged(bench.scratch.appendingPathComponent("elsewhere.pen"))

        #expect(await bench.recorder.payloads(.change, as: ViewerChange.self).isEmpty)
    }

    @Test("The change re-renders: the cache is dropped and the new size is reported")
    func reRendersOnChange() async throws {
        let bench = try await Bench()
        defer { bench.clean() }
        let coordinator = bench.coordinator()
        let file = ViewerFile(url: bench.file)

        let before = try await bench.context.renders.png(artboard: "Cnv01", of: file)
        #expect(before.artboard.width == 400)

        try await PenFileTransaction.run(at: bench.file, identity: "ana", log: ActivityLog(home: bench.scratch), timeout: ViewerFixtures.lockBudget) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Cnv01", properties: ["kind.width": .int(500)]
            )))
        }
        await coordinator.fileChanged(bench.file)

        let after = try await bench.context.renders.png(artboard: "Cnv01", of: file)
        #expect(after.artboard.width == 500)
        #expect(after.png != before.png)
    }
}
