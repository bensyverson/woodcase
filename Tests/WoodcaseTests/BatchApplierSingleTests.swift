//
//  BatchApplierSingleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The single-operation door onto the applier: it throws what it refuses instead of
/// reporting it, because one operation has nothing to carry on with.
@MainActor
struct BatchApplierSingleTests {
    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    @Test("One operation applies and reports what it made")
    func appliesOne() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "frame", "name": "Hero", "width": 10, "height": 10,
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node, parent: NodeAddress("Canvas"))),
            to: document
        )

        #expect(result.status == .applied)
        #expect(result.created.first?.name == "Hero")
        #expect(result.path == "Canvas/Hero")
        #expect(!result.inverse.isEmpty)
    }

    @Test("A refusal is thrown, not reported, and the document is unchanged")
    func throwsWhatItRefuses() throws {
        let document = try makeDocument()
        let before = document.documentRevision

        let title = try #require(NodeAddress("Canvas/Title"))

        #expect(throws: EditingError.self) {
            try BatchApplier.applyOne(
                .set(BatchOperation.SetOp(target: title, props: ["kind.nonsense": 1])),
                to: document
            )
        }
        #expect(document.documentRevision == before)
    }

    @Test("A stale rev throws the conflict rather than a status")
    func throwsARevisionConflict() throws {
        let document = try makeDocument()

        let title = try #require(NodeAddress("Canvas/Title"))

        #expect(throws: EditingError.self) {
            try BatchApplier.applyOne(
                .set(BatchOperation.SetOp(
                    target: title, props: ["kind.content": "Hi"], rev: "0000000000000000"
                )),
                to: document
            )
        }
    }

    @Test("A recorder given to it sees the edit, exactly as a batch would record it")
    func recordsThroughTheRecorder() throws {
        let document = try makeDocument()
        let recorder = ActivityRecorder(
            document: document,
            file: URL(fileURLWithPath: "/tmp/single.pen"),
            identity: "ana",
            batch: "batch-1"
        )

        let title = try #require(NodeAddress("Canvas/Title"))

        _ = try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(target: title, props: ["kind.content": "Hi"])),
            to: document,
            recorder: recorder
        )

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.op == .set)
    }
}
