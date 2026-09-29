//
//  ActivityUndoTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Exercises undo as library API: a caller holding a transaction and a log reverses an
/// edit without going through the CLI, and a step is one whole transaction.
///
/// The step being a transaction is a **behavior change**, ruled on 2026-09-07: a
/// command that logged forty events used to take forty undos, which is not what undo
/// means to the person who ran the command once.
struct ActivityUndoTests {
    // MARK: - Helpers

    private static let fixtureName = "batch.pen"
    private static let canvasID = "Cnv01"
    private static let titleID = "Ttl01"

    private enum TestFailure: Error {
        case fixtureNotFound(String)
        case noSuchNode(String)
    }

    /// A temporary directory holding a canonical copy of the fixture and its own log.
    private func withFixtureAndLog<T>(
        _ body: (URL, ActivityLog) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityUndoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let source = Bundle.module.url(
            forResource: "batch", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw TestFailure.fixtureNotFound(Self.fixtureName)
        }
        let url = directory.appendingPathComponent(Self.fixtureName)
        // Canonical bytes in, so "byte for byte as it was" is a meaningful assertion.
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: source))).write(to: url)
        return try await body(url, ActivityLog(home: directory.appendingPathComponent("home")))
    }

    /// Inserts a group under the canvas.
    private static func insert(_ id: String, named name: String) -> EditOperation {
        .insertNode(EditOperation.InsertNode(
            node: PenNode(
                id: id, common: PenNodeCommon(name: name), kind: .group(PenNode.GroupData())
            ),
            parentID: canvasID
        ))
    }

    /// Renames a node.
    private static func rename(_ nodeID: String, to name: String, in document: EditableDocument) throws -> EditOperation {
        guard var node = document.nodes[nodeID] else { throw TestFailure.noSuchNode(nodeID) }
        node.common.name = name
        return .updateCommon(EditOperation.UpdateCommon(nodeID: nodeID, common: node.common))
    }

    /// Reverses `limit` steps through the library, in its own transaction.
    private static func undo(
        _ url: URL, log: ActivityLog, limit: Int = 1, unit: UndoUnit = .transaction, as identity: String = "ana"
    ) async throws -> ActivityUndo.Result {
        try await PenFileTransaction.run(at: url, identity: identity, log: log) { document, recorder in
            try ActivityUndo.reverse(
                in: document, through: recorder, editing: url, log: log,
                identity: identity, limit: limit, unit: unit
            )
        }.value
    }

    // MARK: - One transaction is one step

    @Test("A transaction of three writes is reversed as one step")
    func oneTransactionIsOneStep() async throws {
        try await withFixtureAndLog { url, log in
            let before = try Data(contentsOf: url)
            try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try recorder.apply(Self.insert("Bdg01", named: "First"))
                try recorder.apply(Self.insert("Bdg02", named: "Second"))
                try recorder.apply(Self.rename(Self.titleID, to: "Renamed", in: document))
            }

            let result = try await Self.undo(url, log: log)
            #expect(result.undone.count == 3)
            // Newest first, so the list reads as the history running backwards.
            #expect(result.undone.map(\.op) == [.set, .add, .add])
            #expect(result.stopped == nil)
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("A limit of two reverses two whole transactions, not two events")
    func limitCountsTransactions() async throws {
        try await withFixtureAndLog { url, log in
            let before = try Data(contentsOf: url)
            try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try recorder.apply(Self.insert("Bdg01", named: "First"))
                try recorder.apply(Self.rename(Self.titleID, to: "One", in: document))
            }
            try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try recorder.apply(Self.insert("Bdg02", named: "Second"))
                try recorder.apply(Self.rename(Self.titleID, to: "Two", in: document))
            }

            let result = try await Self.undo(url, log: log, limit: 2)
            #expect(result.undone.count == 4)
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("The event unit reverses one logged row, leaving the rest of its transaction")
    func eventUnitReversesOneRow() async throws {
        try await withFixtureAndLog { url, log in
            try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try recorder.apply(Self.insert("Bdg01", named: "First"))
                try recorder.apply(Self.rename(Self.titleID, to: "Renamed", in: document))
            }

            let result = try await Self.undo(url, log: log, unit: .event)
            #expect(result.undone.count == 1)
            #expect(result.undone[0].op == .set)

            let after = try await PenFileTransaction.read(at: url) { document in
                (document.nodes[Self.titleID]?.common.name, document.nodes["Bdg01"] != nil)
            }.value
            #expect(after.0 == "Title")
            #expect(after.1)
        }
    }

    // MARK: - Where it stops

    @Test("Another identity's later transaction stops the walk and is named")
    func anotherIdentityStopsTheWalk() async throws {
        try await withFixtureAndLog { url, log in
            try await PenFileTransaction.run(at: url, identity: "ana", log: log) { _, recorder in
                try recorder.apply(Self.insert("Bdg01", named: "First"))
            }
            try await PenFileTransaction.run(at: url, identity: "bo", log: log) { document, recorder in
                try recorder.apply(Self.rename(Self.titleID, to: "Bo", in: document))
            }

            let result = try await Self.undo(url, log: log)
            #expect(result.undone.isEmpty)
            #expect(result.recorded == 2)
            let stopped = try #require(result.stopped)
            guard case let .blockedByOther(event) = stopped else {
                Issue.record("expected the walk to be blocked by bo, not \(stopped)")
                return
            }
            #expect(event.identity == "bo")
        }
    }

    @Test("A file with nothing recorded reverses nothing and refuses nothing")
    func nothingRecordedIsNotARefusal() async throws {
        try await withFixtureAndLog { url, log in
            let result = try await Self.undo(url, log: log)
            #expect(result.undone.isEmpty)
            #expect(result.stopped == nil)
            #expect(result.recorded == 0)
        }
    }

    // MARK: - The two units compose

    @Test("A transaction left half undone by the event unit is finished as one step")
    func theUnitsCompose() async throws {
        try await withFixtureAndLog { url, log in
            let before = try Data(contentsOf: url)
            try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try recorder.apply(Self.insert("Bdg01", named: "First"))
                try recorder.apply(Self.insert("Bdg02", named: "Second"))
                try recorder.apply(Self.rename(Self.titleID, to: "Renamed", in: document))
            }

            // One row back, the finer way…
            #expect(try await Self.undo(url, log: log, unit: .event).undone.count == 1)
            // …and the two rows still standing are the rest of that one command, so a
            // plain undo finishes it rather than reporting nothing left to undo.
            let rest = try await Self.undo(url, log: log)
            #expect(rest.undone.count == 2)
            #expect(rest.stopped == nil)
            #expect(try Data(contentsOf: url) == before)
        }
    }
}
