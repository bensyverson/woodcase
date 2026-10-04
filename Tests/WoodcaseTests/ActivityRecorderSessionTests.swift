//
//  ActivityRecorderSessionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The CLI's write path on the session funnel: the recorder submits through a
/// ``DocumentSession``, so rows carry granular, complete inverses, the ledger sees every
/// write, and a rolled-back batch line leaves no trace in the session either.
@MainActor
struct ActivityRecorderSessionTests {
    private let file = URL(fileURLWithPath: "/tmp/recorder-session.pen")

    private func makeRecorder(
        for document: EditableDocument,
        identity: String? = "ana",
        batch: String = "batch-1"
    ) -> ActivityRecorder {
        ActivityRecorder(document: document, file: file, identity: identity, batch: batch)
    }

    private func batchDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - Granular inverses

    @Test("a whole-struct rename logs the one path it changed, and its forward as written")
    func updateCommonLogsGranularInverse() throws {
        let document = SessionTestDocuments.make()
        let recorder = makeRecorder(for: document)
        var common = try #require(document.nodes["c1"]).common
        common.name = "Renamed"
        let rename = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common))

        let event = try recorder.apply(rename)

        #expect(event.inverse == [
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Child1"])),
        ])
        #expect(event.forward == [rename])
        #expect(document.nodes["c1"]?.common.name == "Renamed")
    }

    @Test("an override write logs one inverse per key, unsetting the key it added")
    func overrideLogsPerKeyInverse() throws {
        let document = SessionTestDocuments.make()
        let recorder = makeRecorder(for: document)

        let event = try recorder.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "inner",
            properties: ["fill": "#00ff00", "opacity": 0.5]
        )))

        #expect(event.inverse == [
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#ff0000"]
            )),
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "ref1", descendantID: "inner", properties: [:], unset: ["opacity"]
            )),
        ])
    }

    @Test("a detach logs a complete inverse that restores the document exactly")
    func detachLogsCompleteInverse() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()
        let recorder = makeRecorder(for: document)

        let event = try recorder.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))
        for operation in event.inverse {
            try document.apply(operation)
        }

        #expect(document.materialize() == before)
    }

    @Test("writing through the session produces the same file bytes as applying directly")
    func sessionWritesSameBytes() throws {
        let direct = SessionTestDocuments.make()
        let viaSession = SessionTestDocuments.make()
        let recorder = makeRecorder(for: viaSession)
        var common = try #require(direct.nodes["c1"]).common
        common.name = "Renamed"
        let operations: [EditOperation] = [
            .updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common)),
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "ref1", descendantID: "inner", properties: ["opacity": 0.5]
            )),
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0)),
            .detachRef(EditOperation.DetachRef(refNodeID: "ref1")),
        ]

        for operation in operations {
            try direct.apply(operation)
            try recorder.apply(operation)
        }

        #expect(try PenParser.encodeForFile(viaSession.materialize()) == PenParser.encodeForFile(direct.materialize()))
    }

    // MARK: - The session sees every write

    @Test("a recorded write is stamped in the session's ledger under the writer's name")
    func recordedWriteIsStamped() throws {
        let document = try batchDocument()
        let recorder = makeRecorder(for: document)

        try BatchApplier.applyOne(
            BatchOperation.decodeJSONL(#"{"op":"set","target":"Canvas/Title","props":{"common.name":"Stamped"}}"#)[0],
            to: document, recorder: recorder
        )

        let stamp = recorder.session.ledger.stamp(for: .property(node: "Ttl01", path: "common.name"))
        #expect(stamp?.author.name == "ana")
        #expect(recorder.session.journaledActivity == recorder.events)
    }

    @Test("a batch line that fails part-way leaves the session's ledger and journal as they were")
    func failedLineLeavesSessionUntouched() throws {
        let document = try batchDocument()
        let recorder = makeRecorder(for: document)
        try BatchApplier.applyOne(
            BatchOperation.decodeJSONL(#"{"op":"set","target":"Canvas/Title","props":{"common.name":"Kept"}}"#)[0],
            to: document, recorder: recorder
        )
        let before = document.materialize()
        let ledger = recorder.session.ledger
        #expect(ledger.stamp(for: .property(node: "Ttl01", path: "common.name")) != nil)

        // The copy inserts, then sets a property no frame has: its first edit lands
        // before its second fails.
        let report = try BatchApplier.apply(
            BatchOperation.decodeJSONL(
                #"{"op":"cp","source":"Canvas/Cards/First","parent":"Canvas","props":{"kind.nonsense":1}}"#
            ),
            to: document, recorder: recorder
        )

        #expect(report.lines.map(\.status) == [.failed])
        #expect(document.materialize() == before)
        #expect(recorder.session.ledger == ledger)
        #expect(recorder.session.journaledActivity.count == 1)
        #expect(recorder.events.count == 1)
    }

    @Test("rolling the recorder's session back drops the events and the edits together")
    func rollbackDropsEventsAndEdits() throws {
        let document = try batchDocument()
        let recorder = makeRecorder(for: document)
        let checkpoint = recorder.session.checkpoint()
        let plan = try BatchApplier.plan(
            BatchOperation.decodeJSONL(#"{"op":"set","target":"Canvas/Title","props":{"common.name":"Renamed"}}"#)[0],
            in: document,
            tags: [:]
        )
        try recorder.apply(plan.operations[0])
        #expect(recorder.events.count == 1)

        try recorder.session.rollback(to: checkpoint)

        #expect(recorder.events.isEmpty)
        #expect(document.node(id: "Ttl01")?.common.name == "Title")
    }

    @Test("a line's reported inverse is the granular one the log records")
    func reportedInverseIsGranular() throws {
        let document = SessionTestDocuments.make()
        let recorder = makeRecorder(for: document)

        let result = try BatchApplier.applyOne(
            BatchOperation.decodeJSONL(
                ##"{"op":"override","target":"Instance/Inner","props":{"fill":"#00ff00","opacity":0.5}}"##
            )[0],
            to: document, recorder: recorder
        )

        #expect(result.inverse == recorder.events.flatMap(\.inverse))
        #expect(result.inverse.count == 2)
    }

    @Test("an atomic batch replays onto the recorder's session, sharing its batch id")
    func atomicReplayGoesThroughSession() throws {
        let document = try batchDocument()
        let recorder = makeRecorder(for: document)

        _ = try BatchApplier.apply(BatchOperation.decodeJSONL("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Primero"}}
        """), to: document, atomic: true, recorder: recorder)

        #expect(recorder.session.ledger.stamp(for: .property(node: "Cd101", path: "common.name")) != nil)
        #expect(Set(recorder.events.map(\.batch)) == ["batch-1"])
    }
}
