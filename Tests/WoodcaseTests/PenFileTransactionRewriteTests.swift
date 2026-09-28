//
//  PenFileTransactionRewriteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers the two writes that are not an edit of a document: rewriting a file in the
/// current format (``PenFileTransaction/migrate(at:identity:log:timeout:effect:rewritingCurrent:diagnostics:)``)
/// and creating one (``PenFileTransaction/create(at:document:identity:log:effect:)``).
/// Both go through the file's lock and leave one row in the activity log — `migrate`
/// and `new` — so the log accounts for every byte woodcase writes.
struct PenFileTransactionRewriteTests {
    // MARK: - Helpers

    private static let legacy217 = #"""
    {"version":"2.17","children":[{"id":"R1","type":"rectangle","width":10,"height":10,
      "effect":{"type":"shadow","shadowType":"inner","color":"#000000","blur":4,"spread":2}}]}
    """#

    /// Runs `body` in a private directory with its own activity log.
    private func withDirectory<T>(_ body: (URL, ActivityLog) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFileTransactionRewriteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ActivityLog(home: directory.appendingPathComponent("log", isDirectory: true), origin: .directory)
        return try await body(directory, log)
    }

    private func events(_ log: ActivityLog) throws -> [ActivityEvent] {
        try ActivityReader(log: log).read().events
    }

    // MARK: - migrate

    @Test("migrate rewrites an older file in the current format and records one migrate event")
    func migrateRewritesAndRecords() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("old.pen")
            try Data(Self.legacy217.utf8).write(to: url)
            let diagnostics = PenDiagnosticCollector()

            let outcome = try await PenFileTransaction.migrate(
                at: url, identity: "bob", log: log, diagnostics: diagnostics
            )

            #expect(outcome.commit == .wrote)
            #expect(outcome.value.declaredVersion == "2.17")
            #expect(outcome.value.writtenVersion == "2.19")
            let written = try Data(contentsOf: url)
            #expect(written == outcome.value.data)
            #expect(!String(decoding: written, as: UTF8.self).contains("spread"))
            #expect(diagnostics.diagnostics.count == 2, "\(diagnostics.diagnostics)")

            let recorded = try events(log)
            #expect(recorded.count == 1)
            let event = try #require(recorded.first)
            #expect(event.op == .migrate)
            #expect(event.identity == "bob")
            #expect(event.inverse.isEmpty)
            let reread = try EditableDocument(from: PenParser.parse(written))
            #expect(event.revision == reread.documentRevision)
        }
    }

    @Test("migrate of a current file in canonical form writes and records nothing")
    func migrateOfCurrentIsUnchanged() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("current.pen")
            try PenParser.encodeForFile(PenDocument(children: [])).write(to: url)
            let before = try Data(contentsOf: url)

            let outcome = try await PenFileTransaction.migrate(at: url, identity: "bob", log: log, rewritingCurrent: true)

            #expect(outcome.commit == .unchanged)
            #expect(try Data(contentsOf: url) == before)
            #expect(try events(log).isEmpty)
        }
    }

    @Test("migrate leaves a current file alone unless asked to rewrite it")
    func migrateSkipsCurrentWithoutForce() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("compact.pen")
            try Data(#"{"version":"2.19","children":[]}"#.utf8).write(to: url)

            let skipped = try await PenFileTransaction.migrate(at: url, identity: "bob", log: log)
            #expect(skipped.commit == .unchanged)
            #expect(try events(log).isEmpty)

            let forced = try await PenFileTransaction.migrate(at: url, identity: "bob", log: log, rewritingCurrent: true)
            #expect(forced.commit == .wrote)
            #expect(try events(log).map(\.op) == [.migrate])
        }
    }

    @Test("A migrate dry run writes and records nothing")
    func migrateDryRun() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("old.pen")
            try Data(Self.legacy217.utf8).write(to: url)

            let outcome = try await PenFileTransaction.migrate(at: url, identity: "bob", log: log, effect: .dryRun)

            #expect(outcome.commit == .previewed)
            #expect(try Data(contentsOf: url) == Data(Self.legacy217.utf8))
            #expect(try events(log).isEmpty)
        }
    }

    @Test("migrate of another major version is refused and changes nothing")
    func migrateRefusesOtherMajor() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("v3.pen")
            let bytes = Data(#"{"version":"3.0","children":[{"id":"R","type":"rectangle","width":1,"height":1}]}"#.utf8)
            try bytes.write(to: url)

            await #expect(throws: PenFormatWriteRefusal.self) {
                _ = try await PenFileTransaction.migrate(at: url, identity: "bob", log: log, rewritingCurrent: true)
            }
            #expect(try Data(contentsOf: url) == bytes)
            #expect(try events(log).isEmpty)
        }
    }

    // MARK: - create

    @Test("create writes the document and records it as the file's first event")
    func createWritesAndRecords() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("new.pen")
            let document = PenDocument(children: [])

            let outcome = try await PenFileTransaction.create(at: url, document: document, identity: "ana", log: log)

            #expect(outcome.commit == .wrote)
            #expect(try Data(contentsOf: url) == PenParser.encodeForFile(document))
            let recorded = try events(log)
            #expect(recorded.map(\.op) == [.new])
            #expect(recorded.first?.identity == "ana")
            #expect(recorded.first?.revision == outcome.value)
            #expect(outcome.value == EditableDocument(from: document).documentRevision)
        }
    }

    @Test("create refuses a path that already exists, and leaves it untouched")
    func createRefusesExisting() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("taken.pen")
            try Data("keep me".utf8).write(to: url)

            await #expect(throws: PenFileError.self) {
                _ = try await PenFileTransaction.create(at: url, document: PenDocument(children: []), identity: "ana", log: log)
            }
            #expect(try Data(contentsOf: url) == Data("keep me".utf8))
            #expect(try events(log).isEmpty)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test("A create dry run writes and records nothing")
    func createDryRun() async throws {
        try await withDirectory { directory, log in
            let url = directory.appendingPathComponent("new.pen")

            let outcome = try await PenFileTransaction.create(
                at: url, document: PenDocument(children: []), identity: "ana", log: log, effect: .dryRun
            )

            #expect(outcome.commit == .previewed)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(try events(log).isEmpty)
        }
    }

    // MARK: - Undo

    @Test("undo passes over a migrate and stops at a new", arguments: [
        (ActivityEvent.Kind.migrate, "stepOverRewrite"), (.new, "reachedCreation"),
    ])
    func undoStep(kind: ActivityEvent.Kind, expected: String) {
        let event = ActivityEvent(
            time: Date(), identity: "bob", file: URL(fileURLWithPath: "/x.pen"), op: kind, revision: "r"
        )
        let step = UndoStep.decide(event, currentRevision: "r", identity: "ana", allIdentities: false, afterUndo: false)
        let name = switch step {
        case .stepOverRewrite: "stepOverRewrite"
        case .reachedCreation: "reachedCreation"
        default: "\(step)"
        }
        #expect(name == expected)
    }
}
