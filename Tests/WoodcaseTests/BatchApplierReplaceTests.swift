//
//  BatchApplierReplaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The `replace` line of the batch grammar: it settles the new subtree's ids the way
/// `add` does, keeps the target's own id, and logs one event.
@MainActor
@Suite("The replace batch operation")
struct BatchApplierReplaceTests {
    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func node(_ json: AnyCodable) throws -> PenNode {
        try PenSubtreeDecoder.node(from: json)
    }

    private func address(_ raw: String) throws -> NodeAddress {
        try #require(NodeAddress(raw))
    }

    // MARK: - Applying

    @Test("A replace keeps the target's id and index, and generates the ids it was not given")
    func replacesInPlace() throws {
        let document = try makeDocument()
        let result = try BatchApplier.applyOne(
            .replace(BatchOperation.ReplaceOp(
                target: address("Canvas/Cards"),
                node: node([
                    "type": "frame", "name": "Cards", "width": 380, "height": 200,
                    "children": [["type": "text", "name": "Only", "content": "hi"]],
                ])
            )),
            to: document
        )

        #expect(result.status == .applied)
        #expect(result.path == "Canvas/Cards")
        #expect(result.created.first?.id == "Crd01")
        #expect(result.created.first?.children.map(\.name) == ["Only"])
        #expect(document.children["Cnv01"] == ["Ttl01", "Crd01"])
        let onlyID = try #require(result.created.first?.children.first?.id)
        #expect(PenID.isValid(onlyID))
        #expect(document.namePath(of: onlyID) == "Canvas/Cards/Only")
    }

    @Test("A supplied root id equal to the target is accepted")
    func acceptsTheTargetsOwnID() throws {
        let document = try makeDocument()
        let result = try BatchApplier.applyOne(
            .replace(BatchOperation.ReplaceOp(
                target: address("Canvas/Cards"),
                node: node(["id": "Crd01", "type": "frame", "name": "Cards"])
            )),
            to: document
        )

        #expect(result.created.first?.id == "Crd01")
    }

    @Test("A supplied root id that is not the target's is refused, and says the id is kept")
    func refusesADifferentRootID() throws {
        let document = try makeDocument()
        #expect(throws: BatchError.replacementIDMismatch(
            address: "Canvas/Cards", supplied: "Nope1", kept: "Crd01"
        )) {
            try BatchApplier.applyOne(
                .replace(BatchOperation.ReplaceOp(
                    target: address("Canvas/Cards"),
                    node: node(["id": "Nope1", "type": "frame", "name": "Cards"])
                )),
                to: document
            )
        }
        #expect(document.nodes["Cd101"] != nil)
    }

    @Test("An unnamed node in the replacement is refused, as it is in an add")
    func refusesAnUnnamedNode() throws {
        let document = try makeDocument()
        #expect(throws: BatchError.self) {
            try BatchApplier.applyOne(
                .replace(BatchOperation.ReplaceOp(
                    target: address("Canvas/Cards"),
                    node: node([
                        "type": "frame", "name": "Cards",
                        "children": [["type": "text", "content": "hi"]],
                    ])
                )),
                to: document
            )
        }
    }

    @Test("An id the replaced subtree already held may be kept")
    func keepsAnIDFromTheOldSubtree() throws {
        let document = try makeDocument()
        let result = try BatchApplier.applyOne(
            .replace(BatchOperation.ReplaceOp(
                target: address("Canvas/Cards"),
                node: node([
                    "type": "frame", "name": "Cards",
                    "children": [["id": "Cd101", "type": "text", "name": "Kept"]],
                ])
            )),
            to: document
        )

        #expect(result.created.first?.children.map(\.id) == ["Cd101"])
        #expect(document.namePath(of: "Cd101") == "Canvas/Cards/Kept")
    }

    @Test("rev guards the target node")
    func revisionGuardsTheTarget() throws {
        let document = try makeDocument()
        #expect(throws: EditingError.self) {
            try BatchApplier.applyOne(
                .replace(BatchOperation.ReplaceOp(
                    target: address("Canvas/Cards"),
                    node: node(["type": "frame", "name": "Cards"]),
                    rev: "0000000000000000"
                )),
                to: document
            )
        }
        #expect(document.nodes["Cd101"] != nil)
    }

    // MARK: - Logging

    @Test("A replace logs one event, and its inverse restores the old subtree")
    func logsOneReversibleEvent() throws {
        let document = try makeDocument()
        let before = try document.materializeSubtree(rootID: "Crd01")
        let recorder = ActivityRecorder(
            document: document,
            file: URL(fileURLWithPath: "/tmp/batch.pen"),
            identity: "ana",
            batch: "batch-1"
        )

        try BatchApplier.applyOne(
            .replace(BatchOperation.ReplaceOp(
                target: address("Canvas/Cards"),
                node: node(["type": "frame", "name": "Cards", "children": []])
            )),
            to: document,
            recorder: recorder
        )

        #expect(recorder.events.count == 1)
        let event = try #require(recorder.events.first)
        #expect(event.op == .replace)
        #expect(event.nodes == ["Crd01"])
        #expect(event.paths == ["Canvas/Cards"])

        for operation in event.inverse {
            try document.apply(operation)
        }
        #expect(try document.materializeSubtree(rootID: "Crd01") == before)
    }

    // MARK: - The wire format

    @Test("A replace line round-trips through the batch grammar")
    func roundTripsThroughJSONL() throws {
        let line = #"{"node":{"id":"Crd01","name":"Cards","type":"frame"},"op":"replace","rev":"abc","target":"Canvas/Cards"}"#
        let decoded = try BatchOperation.decodeJSONL(line)
        #expect(decoded.count == 1)
        guard case let .replace(op) = decoded[0] else {
            Issue.record("expected a replace, got \(decoded[0])")
            return
        }
        #expect(op.target.description == "Canvas/Cards")
        #expect(op.node.id == "Crd01")
        #expect(op.node.common.name == "Cards")
        #expect(op.rev == "abc")
        #expect(decoded[0].verb == .replace)
        #expect(decoded[0].targetAddress?.description == "Canvas/Cards")
        #expect(decoded[0].rev == "abc")
        #expect(decoded[0].declaredTag == nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        #expect(try String(decoding: encoder.encode(decoded[0]), as: UTF8.self) == line)
    }

    @Test("An id the subtree leaves out reads as unsupplied, as it does in an add")
    func acceptsAnOmittedRootID() throws {
        let decoded = try BatchOperation.decodeJSONL(
            #"{"op":"replace","target":"Canvas/Cards","node":{"type":"frame","name":"Cards"}}"#
        )
        guard case let .replace(op) = decoded[0] else {
            Issue.record("expected a replace, got \(decoded[0])")
            return
        }
        #expect(op.node.id == PenSubtreeDecoder.unsuppliedID)
    }

    @Test("The grammar printed by apply --help documents the replace line")
    func grammarDocumentsReplace() {
        #expect(BatchOperation.grammar.contains(#"{"op":"replace","target":ADDR,"node":SUBTREE,"rev":REV}"#))
    }
}
