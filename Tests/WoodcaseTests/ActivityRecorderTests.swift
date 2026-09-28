//
//  ActivityRecorderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises the seam between ``PenFileTransaction`` and the activity log: a body
/// that edits through its ``ActivityRecorder`` produces one event per applied
/// operation, and only when the transaction actually commits.
struct ActivityRecorderTests {
    // MARK: - Helpers

    private static let fixtureName = "layout-vertical.pen"
    private static let targetNodeID = "jSUCH"

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    /// A temporary directory holding both a copy of the fixture and the log.
    private func withFixtureAndLog<T>(
        _ body: (URL, ActivityLog) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityRecorderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = (Self.fixtureName as NSString).deletingPathExtension
        let ext = (Self.fixtureName as NSString).pathExtension
        guard let source = Bundle.module.url(
            forResource: base, withExtension: ext, subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound(Self.fixtureName)
        }
        let url = directory.appendingPathComponent(Self.fixtureName)
        try FileManager.default.copyItem(at: source, to: url)
        return try await body(url, ActivityLog(home: directory.appendingPathComponent("home")))
    }

    /// Renames the target node, returning the operation that does it.
    private static func renameOperation(
        _ document: EditableDocument, to name: String
    ) throws -> EditOperation {
        var node = try #require(document.nodes[targetNodeID])
        node.common.name = name
        return .updateCommon(EditOperation.UpdateCommon(nodeID: targetNodeID, common: node.common))
    }

    // MARK: - One event per applied operation

    @Test("Three operations through the recorder produce three events with the revision after each")
    func threeOperationsProduceThreeEvents() async throws {
        try await withFixtureAndLog { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: "logger", log: log
            ) { document, recorder in
                try recorder.apply(Self.renameOperation(document, to: "first"))
                let afterFirst = document.documentRevision
                try recorder.apply(Self.renameOperation(document, to: "second"))
                try recorder.apply(.addThemeAxis(
                    EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"])
                ))
                return (afterFirst, document.documentRevision)
            }
            #expect(outcome.didWrite)

            let page = try ActivityReader(log: log).read()
            #expect(page.events.count == 3)
            #expect(page.events.map(\.op) == [.set, .set, .theme])
            #expect(page.events[0].revision == outcome.value.0)
            #expect(page.events[2].revision == outcome.value.1)
            #expect(Set(page.events.map(\.revision)).count == 3)

            // Every event of one transaction shares a batch id.
            let batches = Set(page.events.compactMap(\.batch))
            #expect(batches.count == 1)

            // Attribution: identity, absolute file path, node ids and name paths.
            #expect(page.events.allSatisfy { $0.identity == "logger" })
            #expect(page.events[0].file == ActivityEvent.canonicalPath(for: url))
            #expect(page.events[0].nodes == [Self.targetNodeID])
            #expect(page.events[0].paths == ["layout-vertical/first"])
            #expect(page.events[2].nodes.isEmpty)
        }
    }

    @Test("The recorded inverse undoes the operation it was recorded for")
    func recordedInverseUndoesTheOperation() async throws {
        try await withFixtureAndLog { url, log in
            try await PenFileTransaction.run(at: url, identity: "logger", log: log) { document, recorder in
                try recorder.apply(Self.renameOperation(document, to: "renamed"))
            }

            let inverse = try #require(ActivityReader(log: log).read().events.first?.inverse)
            #expect(inverse.count == 1)

            try await PenFileTransaction.run(at: url) { document in
                for operation in inverse {
                    try document.apply(operation)
                }
                #expect(document.nodes[Self.targetNodeID]?.common.name == "child-1")
            }
        }
    }

    // MARK: - Nothing written, nothing logged

    @Test("A transaction that writes nothing appends nothing")
    func noOpTransactionLogsNothing() async throws {
        try await withFixtureAndLog { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: "logger", log: log
            ) { document, _ in
                document.nodes.count
            }
            #expect(outcome.didWrite == false)
            #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }

    @Test("A transaction whose body throws appends nothing")
    func throwingTransactionLogsNothing() async throws {
        struct Boom: Error {}
        try await withFixtureAndLog { url, log in
            await #expect(throws: Boom.self) {
                try await PenFileTransaction.run(at: url, identity: "logger", log: log) { document, recorder in
                    try recorder.apply(Self.renameOperation(document, to: "renamed"))
                    throw Boom()
                }
            }
            #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }

    // MARK: - The unattributed writer

    @Test("Without an identity the edit is still logged, attributed to nobody")
    func unattributedTransactionLogsWithAnEmptyIdentity() async throws {
        try await withFixtureAndLog { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: nil, log: log
            ) { document, recorder in
                try recorder.apply(Self.renameOperation(document, to: "renamed")).identity
            }
            #expect(outcome.didWrite)
            #expect(outcome.value == ActivityEvent.unattributed)

            let page = try ActivityReader(log: log).read()
            #expect(page.events.count == 1)
            #expect(page.events.first?.identity == "")
            #expect(page.events.first?.op == .set)
            #expect(page.events.first?.paths == ["layout-vertical/renamed"])
        }
    }

    @Test("An unattributed event carries a usable inverse, so it is history like any other")
    func unattributedEventIsUndoable() async throws {
        try await withFixtureAndLog { url, log in
            try await PenFileTransaction.run(at: url, identity: nil, log: log) { document, recorder in
                try recorder.apply(Self.renameOperation(document, to: "renamed"))
            }

            let event = try #require(ActivityReader(log: log).read().events.first)
            #expect(event.inverse.count == 1)
            #expect(event.revision.isEmpty == false)
        }
    }

    @Test("A body that never touches its recorder logs nothing, identity or not")
    func documentOnlyEditsAreNotLogged() async throws {
        try await withFixtureAndLog { url, log in
            let outcome = try await PenFileTransaction.run(at: url, identity: nil, log: log) { document, _ in
                try document.apply(Self.renameOperation(document, to: "renamed"))
            }
            #expect(outcome.didWrite)
            #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }

    // MARK: - Labelling

    @Test("A caller-supplied kind labels the event, so undo can name itself")
    func callerSuppliedKindLabelsTheEvent() async throws {
        try await withFixtureAndLog { url, log in
            try await PenFileTransaction.run(at: url, identity: "logger", log: log) { document, recorder in
                try recorder.apply(Self.renameOperation(document, to: "restored"), as: .undo)
            }
            #expect(try ActivityReader(log: log).read().events.map(\.op) == [.undo])
        }
    }

    // MARK: - Optimistic concurrency

    @Test("A stale expected revision throws and records nothing")
    func staleRevisionRecordsNothing() async throws {
        try await withFixtureAndLog { url, log in
            await #expect(throws: EditingError.self) {
                try await PenFileTransaction.run(at: url, identity: "logger", log: log) { document, recorder in
                    try recorder.apply(
                        Self.renameOperation(document, to: "renamed"),
                        expecting: [Self.targetNodeID: "stale"]
                    )
                }
            }
            #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }
}
