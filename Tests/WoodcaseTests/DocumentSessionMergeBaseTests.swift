//
//  DocumentSessionMergeBaseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The merge base is built only when a merge needs it, so a one-shot CLI session never
/// pays to copy the document.
@MainActor
struct DocumentSessionMergeBaseTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))

    private func rename(_ nodeID: String, to name: String) -> SessionOrigin {
        .local(LocalEdit(operations: [
            .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": .string(name)])),
        ]))
    }

    @Test("a session builds its base on first use, as the document it was given")
    func baseIsBuiltOnFirstUse() throws {
        let original = SessionTestDocuments.make().materialize()
        let session = DocumentSession(document: original, author: ana)
        try session.submit(rename("c1", to: "Edited"))

        #expect(!session.hasBuiltBase)
        #expect(session.base?.materialize() == original)
        #expect(session.hasBuiltBase)
    }

    @Test("noting a sync replaces the base with what was written")
    func noteSyncedReplacesBase() throws {
        let session = DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana)
        try session.submit(rename("c1", to: "Written"))
        let written = session.document.materialize()

        session.noteSynced(written, through: session.sequence)

        #expect(session.base?.materialize() == written)
    }

    @Test("a wrapping session told no file state has no base")
    func wrappingWithoutFileStateHasNoBase() {
        let session = DocumentSession(editing: SessionTestDocuments.make(), author: ana, file: nil)
        #expect(session.base == nil)
    }

    @Test("a recorder-less batch writes without building a base")
    func recorderlessBatchBuildsNoBase() throws {
        let document = SessionTestDocuments.make()
        let session = BatchApplier.writingSession(editing: document, recorder: nil)
        try session.submit(rename("c1", to: "Batched"))
        #expect(!session.hasBuiltBase)
    }

    @Test("a CLI transaction writes and logs without building a base")
    func transactionBuildsNoBase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentSessionMergeBaseTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let url = directory.appendingPathComponent("layout-vertical.pen")
        try FileManager.default.copyItem(at: source, to: url)
        let log = ActivityLog(home: directory.appendingPathComponent("home"))

        let outcome = try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "jSUCH", properties: ["common.name": "renamed"]
            )))
            #expect(document === recorder.session.document)
            return recorder.session.hasBuiltBase
        }

        #expect(outcome.didWrite)
        #expect(outcome.value == false)
    }

    @Test("a transaction's session knows the parsed file as its base when asked")
    func transactionBaseIsParsedFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentSessionMergeBaseTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let url = directory.appendingPathComponent("layout-vertical.pen")
        try FileManager.default.copyItem(at: source, to: url)
        let parsed = try PenParser.parse(contentsOf: url)

        let matches = try await PenFileTransaction.run(
            at: url, identity: "ana", log: ActivityLog(home: directory.appendingPathComponent("home"))
        ) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: "jSUCH", properties: ["common.name": "renamed"]
            )))
            return recorder.session.base?.materialize() == parsed
        }.value

        #expect(matches)
    }
}
