//
//  ChangedArtboardsTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// A `change` says which artboards it *re-rendered* — every one of them — and, now,
/// which ones it *touched*. Follow needs the second: an artboard to move to.
struct ChangedArtboardsTests {
    /// An SSE client that keeps what it was written.
    private actor Recorder: SSEWriter {
        private(set) var writes: [String] = []

        func write(_ text: String) async -> Bool {
            writes.append(text)
            return true
        }

        func close() async {}

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

    /// The prepared form of `batch.pen`, which has three artboards: a canvas, a board
    /// holding an instance, and the component definition that instance is of.
    private func prepared() async throws -> (PreparedDocument, URL) {
        let scratch = try ViewerFixtures.scratch()
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let cache = ViewerFixtures.renders()
        return try await (cache.prepared(ViewerFile(url: file)), scratch)
    }

    @Test("A node's artboard is the top-level frame it sits under")
    func artboardOfANode() async throws {
        let (document, scratch) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        #expect(document.artboardIDs(containing: ["Ttl01"]) == ["Cnv01"])
        #expect(document.artboardIDs(containing: ["Cd201"]) == ["Cnv01"])
        #expect(document.artboardIDs(containing: ["Brd01"]) == ["Brd01"])
    }

    @Test("An artboard the node is not in is not named")
    func unrelatedArtboardsAreNotNamed() async throws {
        let (document, scratch) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        #expect(document.artboardIDs(containing: ["Nope1"]) == [])
        #expect(document.artboardIDs(containing: []) == [])
    }

    @Test("A node edited inside a definition names the definition and every artboard placing it")
    func expandedCopiesCount() async throws {
        let (document, scratch) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // `Lbl01` lives in the `Cmp01` definition, and expansion places a copy of it
        // inside `Brd01` under an id-path (`Chi01/Lbl01`). Both renders changed, so
        // both are named, in document order.
        #expect(document.artboardIDs(containing: ["Lbl01"]) == ["Brd01", "Cmp01"])
    }

    @Test("Several touched nodes give their artboards once each, in document order")
    func dedupesInDocumentOrder() async throws {
        let (document, scratch) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        #expect(document.artboardIDs(containing: ["Brd01", "Ttl01", "Cd101"]) == ["Cnv01", "Brd01"])
    }

    @Test("The change event carries the artboards the write touched, not only the ones re-rendered")
    func changeNamesTheTouchedArtboards() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let context = ViewerFixtures.context(files: [file], home: scratch)
        let recorder = Recorder()
        await context.events.add(recorder)
        let coordinator = ChangeCoordinator(
            context: context, matchWindow: .milliseconds(300), pollInterval: .milliseconds(20)
        )

        await coordinator.logged(ActivityEvent(
            time: Date(), identity: "ana", file: file,
            op: .set, nodes: ["Ttl01"], paths: ["Canvas/Title"], revision: "r1"
        ))
        await coordinator.fileChanged(file)

        let change = try #require(await recorder.payloads(.change, as: ViewerChange.self).first)
        #expect(change.artboards == ["Cnv01", "Brd01", "Cmp01"])
        #expect(change.changedArtboards == ["Cnv01"])
        #expect(change.identity == "ana")
    }

    @Test("A write nobody logged touches no artboard, because nobody said which")
    func unattributedChangeTouchesNothing() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let context = ViewerFixtures.context(files: [file], home: scratch)
        let recorder = Recorder()
        await context.events.add(recorder)
        let coordinator = ChangeCoordinator(
            context: context, matchWindow: .milliseconds(100), pollInterval: .milliseconds(20)
        )

        await coordinator.fileChanged(file)

        let change = try #require(await recorder.payloads(.change, as: ViewerChange.self).first)
        #expect(change.changedArtboards.isEmpty)
    }

    @Test("A ref's own id names the artboard it is placed in, not nothing")
    func artboardOfABareRef() async throws {
        let (document, scratch) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Expansion replaces the `Chi01` ref with the `Cmp01` definition under the
        // ref's id (`Chi01/Cmp01`), so the authored id is a *prefix* of the expanded
        // one rather than its last component.
        #expect(document.artboardIDs(containing: ["Chi01"]) == ["Brd01"])
    }

    @Test("A set on a bare ref reports the artboard the ref sits in")
    func aWriteToARefNamesItsArtboard() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFixtures.copy("batch.pen", into: scratch)
        let log = ActivityLog(home: scratch)
        let context = ViewerFixtures.context(files: [file], home: scratch)
        let recorder = Recorder()
        await context.events.add(recorder)
        let coordinator = ChangeCoordinator(
            context: context, matchWindow: .milliseconds(300), pollInterval: .milliseconds(20)
        )

        try await PenFileTransaction.run(
            at: file, identity: "ana", log: log, timeout: ViewerFixtures.lockBudget
        ) { _, activity in
            try activity.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "Chi01", properties: ["common.name": .string("Renamed")]
            )))
        }
        let logged = try #require(try ActivityReader(log: log).read().events.last)
        #expect(logged.nodes == ["Chi01"])

        await coordinator.logged(logged)
        await coordinator.fileChanged(file)

        let change = try #require(await recorder.payloads(.change, as: ViewerChange.self).first)
        #expect(change.changedArtboards == ["Brd01"])
    }
}
