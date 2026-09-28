//
//  BatchApplierRecorderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Exercises the applier's ``ActivityRecorder`` hook: a batch applied with a recorder
/// logs exactly what the same edits log when applied one at a time, and a line that
/// rolls back logs nothing.
@MainActor
struct BatchApplierRecorderTests {
    // MARK: - Helpers

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func makeRecorder(
        for document: EditableDocument,
        identity: String? = "ana",
        batch: String = "batch-1"
    ) -> ActivityRecorder {
        ActivityRecorder(
            document: document,
            file: URL(fileURLWithPath: "/tmp/batch.pen"),
            identity: identity,
            batch: batch
        )
    }

    private func ops(_ jsonl: String) throws -> [BatchOperation] {
        try BatchOperation.decodeJSONL(jsonl)
    }

    /// Everything about an event that the edit determines. `time` is the clock and
    /// `batch` belongs to the recorder, so neither can be compared across recorders.
    private func fingerprint(_ event: ActivityEvent) -> String {
        "\(event.op)|\(event.nodes)|\(event.paths)|\(event.inverse)|\(event.revision)"
    }

    private let twoGoodLines = """
    {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
    {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Primero"}}
    """

    // MARK: - One event per applied edit

    @Test("A recorded batch logs one event per applied line, all sharing one batch id")
    func recordsEveryAppliedLine() throws {
        let document = try makeDocument()
        let recorder = makeRecorder(for: document)
        let report = try BatchApplier.apply(ops(twoGoodLines), to: document, recorder: recorder)

        #expect(report.lines.map(\.status) == [.applied, .applied])
        #expect(recorder.events.count == 2)
        #expect(recorder.events.map(\.nodes) == [["Ttl01"], ["Cd101"]])
        #expect(Set(recorder.events.map(\.batch)) == ["batch-1"])
    }

    @Test("A batch records exactly what the same edits record one at a time")
    func matchesHandWrittenRecorderCalls() throws {
        let batch = try ops(twoGoodLines)

        let applied = try makeDocument()
        let appliedRecorder = makeRecorder(for: applied)
        _ = BatchApplier.apply(batch, to: applied, recorder: appliedRecorder)

        let manual = try makeDocument()
        let manualRecorder = makeRecorder(for: manual)
        for operation in batch {
            let plan = try BatchApplier.plan(operation, in: manual, tags: [:])
            for (index, edit) in plan.operations.enumerated() {
                try manualRecorder.apply(edit, expecting: index == 0 ? plan.expecting : [:])
            }
        }

        #expect(appliedRecorder.events.map(fingerprint) == manualRecorder.events.map(fingerprint))
        #expect(!appliedRecorder.events.isEmpty)
    }

    @Test("A batch applied without a recorder still applies")
    func recorderIsOptional() throws {
        let document = try makeDocument()
        let report = try BatchApplier.apply(ops(twoGoodLines), to: document)
        #expect(report.lines.map(\.status) == [.applied, .applied])
    }

    @Test("An unattributed recorder records the batch, attributed to nobody")
    func unattributedRecordsEveryLine() throws {
        // A batch run without an identity used to record nothing at all, which made
        // every unattributed `apply` invisible to the log its own report claims to
        // describe. It now records exactly what an attributed batch would, naming
        // nobody: see `ActivityEvent.unattributed`.
        let document = try makeDocument()
        let recorder = makeRecorder(for: document, identity: nil)
        let report = try BatchApplier.apply(ops(twoGoodLines), to: document, recorder: recorder)

        #expect(report.lines.map(\.status) == [.applied, .applied])
        #expect(recorder.events.count == 2)
        #expect(recorder.events.allSatisfy { $0.identity == ActivityEvent.unattributed })
        #expect(recorder.events.allSatisfy { !$0.inverse.isEmpty })
        #expect(document.node(id: "Cd101")?.common.name == "Primero")
    }

    // MARK: - Rollback

    @Test("A line that fails half way through leaves no events behind")
    func failedLineRecordsNothing() throws {
        let document = try makeDocument()
        let recorder = makeRecorder(for: document)
        // The copy inserts, then sets a property no frame has: the line's first edit
        // is applied and recorded before its second edit fails.
        let report = try BatchApplier.apply(ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"cp","source":"Canvas/Cards/First","parent":"Canvas","props":{"kind.nonsense":1}}
        """), to: document, recorder: recorder)

        #expect(report.lines.map(\.status) == [.applied, .failed])
        #expect(recorder.events.count == 1)
        #expect(recorder.events.map(\.nodes) == [["Ttl01"]])
    }

    @Test("Discarding events after a checkpoint leaves the edits themselves in place")
    func discardEventsKeepsTheEdits() throws {
        let document = try makeDocument()
        let recorder = makeRecorder(for: document)
        let checkpoint = recorder.events.count
        let plan = try BatchApplier.plan(
            ops("""
            {"op":"set","target":"Canvas/Title","props":{"common.name":"Renamed"}}
            """)[0],
            in: document,
            tags: [:]
        )
        try recorder.apply(plan.operations[0])
        #expect(recorder.events.count == checkpoint + 1)

        recorder.discardEvents(after: checkpoint)
        #expect(recorder.events.isEmpty)
        #expect(document.node(id: "Ttl01")?.common.name == "Renamed")
    }

    // MARK: - Atomic batches

    @Test("An atomic batch that fails records nothing")
    func atomicFailureRecordsNothing() throws {
        let document = try makeDocument()
        let recorder = makeRecorder(for: document)
        let report = try BatchApplier.apply(ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        """), to: document, atomic: true, recorder: recorder)

        #expect(report.lines.map(\.status) == [.cascaded, .failed])
        #expect(recorder.events.isEmpty)
    }

    @Test("An atomic batch that succeeds records the replay onto the real document")
    func atomicSuccessRecordsTheReplay() throws {
        let document = try makeDocument()
        let recorder = makeRecorder(for: document)
        let report = try BatchApplier.apply(
            ops(twoGoodLines), to: document, atomic: true, recorder: recorder
        )

        #expect(report.lines.map(\.status) == [.applied, .applied])
        #expect(recorder.events.count == 2)
        #expect(recorder.events.map(\.nodes) == [["Ttl01"], ["Cd101"]])
        #expect(document.node(id: "Cd101")?.common.name == "Primero")
    }

    // MARK: - Retry

    @Test("A retry records only the lines it re-ran")
    func retryRecordsOnlyRepairedLines() throws {
        let document = try makeDocument()
        let first = makeRecorder(for: document)
        let broken = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        """)
        let report = BatchApplier.apply(broken, to: document, recorder: first)
        #expect(first.events.count == 1)

        let second = makeRecorder(for: document, batch: "batch-2")
        let repaired = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Primero"}}
        """)
        let retried = BatchApplier.retry(
            repaired, report: report, to: document, recorder: second
        )

        #expect(retried.lines.map(\.status) == [.applied, .applied])
        #expect(second.events.count == 1)
        #expect(second.events.map(\.nodes) == [["Cd101"]])
    }
}
