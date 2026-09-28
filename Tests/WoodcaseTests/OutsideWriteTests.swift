//
//  OutsideWriteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises what a transaction does when it opens a file the activity log cannot
/// account for: it says so once, records the fact, and carries on.
struct OutsideWriteTests {
    // MARK: - Helpers

    private static let fixtureName = "batch.pen"
    private static let titleID = "Ttl01"

    private enum TestFailure: Error {
        case fixtureNotFound(String)
        case noSuchNode(String)
    }

    /// A temporary directory holding a copy of the fixture and its own log.
    private func withFixtureAndLog<T>(
        _ body: (URL, ActivityLog) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideWriteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let source = Bundle.module.url(
            forResource: "batch", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw TestFailure.fixtureNotFound(Self.fixtureName)
        }
        let url = directory.appendingPathComponent(Self.fixtureName)
        try FileManager.default.copyItem(at: source, to: url)
        return try await body(url, ActivityLog(home: directory.appendingPathComponent("home")))
    }

    /// Renames the title through the recorder, as any write verb would.
    @discardableResult
    private static func rename(
        _ url: URL, log: ActivityLog, to name: String
    ) async throws -> PenFileTransaction.Outcome<Void> {
        try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
            guard var node = document.nodes[titleID] else { throw TestFailure.noSuchNode(titleID) }
            node.common.name = name
            try recorder.apply(.updateCommon(
                EditOperation.UpdateCommon(nodeID: titleID, common: node.common)
            ))
        }
    }

    /// Rewrites the file the way a stranger would: parse the JSON, change it, write it
    /// back — no lock, no log, no revision.
    private static func rewriteFromOutside(_ url: URL, name: String) throws {
        var document = try PenParser.parse(Data(contentsOf: url))
        guard !document.children.isEmpty else { throw TestFailure.noSuchNode("children") }
        document.children[0].common.name = name
        try PenParser.encodeForFile(document).write(to: url)
    }

    /// Every event in the log, oldest first.
    private static func events(in log: ActivityLog) throws -> [ActivityEvent] {
        try ActivityReader(log: log).read().events
    }

    // MARK: - A file the log does explain

    @Test("A file only woodcase has written is current, and says nothing")
    func woodcaseOnlyIsQuiet() async throws {
        try await withFixtureAndLog { url, log in
            let first = try await Self.rename(url, log: log, to: "One")
            #expect(first.lineage == .unlogged)
            #expect(first.lineage.note(naming: url) == nil)

            let second = try await Self.rename(url, log: log, to: "Two")
            #expect(!second.lineage.isDiverged)
            #expect(second.lineage.note(naming: url) == nil)
            #expect(try Self.events(in: log).allSatisfy { $0.op != .external })
        }
    }

    // MARK: - A file somebody else wrote

    @Test("A write after an outside rewrite notes it, records it once, and carries on")
    func outsideWriteIsNotedAndRecorded() async throws {
        try await withFixtureAndLog { url, log in
            try await Self.rename(url, log: log, to: "One")
            let known = try #require(Self.events(in: log).last)
            try Self.rewriteFromOutside(url, name: "Stranger")
            let found = try await PenFileTransaction.read(at: url) { $0.documentRevision }.value

            let second = try await Self.rename(url, log: log, to: "Two")
            #expect(second.lineage == .diverged(since: known, found: found))
            let note = try #require(second.lineage.note(naming: url))
            #expect(note.contains("was rewritten outside woodcase since rev"))
            #expect(note.contains(String(known.revision.prefix(8))))

            // The row goes in first, carrying the revision the file was found at, so
            // the history reads in order and the hole has a boundary.
            let events = try Self.events(in: log)
            #expect(events.map(\.op) == [.set, .external, .set])
            #expect(events[1].revision == found)
            #expect(events[1].identity == ActivityEvent.unattributed)
            #expect(events[1].inverse.isEmpty)
            #expect(events[1].batch == nil)

            // And once recorded, the invariant holds again: the next write is quiet.
            let third = try await Self.rename(url, log: log, to: "Three")
            #expect(!third.lineage.isDiverged)
            #expect(third.lineage.note(naming: url) == nil)
            #expect(try Self.events(in: log).count(where: { $0.op == .external }) == 1)
        }
    }

    @Test("The very first write to a file is not an outside write")
    func firstWriteIsNotADivergence() async throws {
        try await withFixtureAndLog { url, log in
            // The fixture came from somewhere, and nobody logged that. A file with no
            // history makes no claim, so reporting one would cry wolf on every file.
            let outcome = try await Self.rename(url, log: log, to: "One")
            #expect(outcome.lineage == .unlogged)
            #expect(try Self.events(in: log).map(\.op) == [.set])
        }
    }

    // MARK: - Undo stops at the boundary

    @Test("Undo refuses to step past an external row, naming when it happened")
    func undoStopsAtTheOutsideEdit() async throws {
        try await withFixtureAndLog { url, log in
            try await Self.rename(url, log: log, to: "One")
            try Self.rewriteFromOutside(url, name: "Stranger")
            try await Self.rename(url, log: log, to: "Two")

            // The first undo reverses the write that came after the outside edit.
            let first = try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try ActivityUndo.reverse(
                    in: document, through: recorder, editing: url, log: log, identity: "ana"
                )
            }.value
            #expect(first.undone.count == 1)

            // The second meets the row, which has no inverse to replay.
            let second = try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try ActivityUndo.reverse(
                    in: document, through: recorder, editing: url, log: log, identity: "ana"
                )
            }.value
            #expect(second.undone.isEmpty)
            let stopped = try #require(second.stopped)
            guard case let .blockedByExternal(row) = stopped else {
                Issue.record("expected to be blocked by the outside edit, not \(stopped)")
                return
            }
            #expect(row.op == .external)
        }
    }
}
