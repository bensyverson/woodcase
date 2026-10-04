//
//  BatchApplierEditTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``BatchApplier/applyEdit(_:to:recorder:)``: the door for an ``EditOperation`` the
/// batch grammar has no verb for, through the same session funnel as every line.
@MainActor
struct BatchApplierEditTests {
    private let remove = EditOperation.removeVariable(EditOperation.RemoveVariable(name: "primary"))

    @Test("without a recorder the edit goes through a session and comes back with its inverse")
    func recorderlessEditIsCommitted() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()

        let change = try BatchApplier.applyEdit(remove, to: document)

        #expect(document.variables?["primary"] == nil)
        #expect(change.applied.map(\.forward) == [remove])
        #expect(change.activity.isEmpty)
        for step in change.applied.flatMap(\.inverse) {
            try document.apply(step.operation)
        }
        #expect(document.materialize() == before)
    }

    @Test("with a recorder the edit is recorded as one event")
    func recordedEditIsLogged() throws {
        let document = SessionTestDocuments.make()
        let recorder = ActivityRecorder(
            document: document, file: URL(fileURLWithPath: "/tmp/apply-edit.pen"), identity: "ana", batch: "b"
        )

        try BatchApplier.applyEdit(remove, to: document, recorder: recorder)

        #expect(recorder.events.map(\.op) == [.var])
        #expect(recorder.events.first?.forward == [remove])
    }

    @Test("a refused edit leaves the document as it was")
    func refusedEditChangesNothing() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()

        #expect(throws: EditingError.self) {
            try BatchApplier.applyEdit(
                .removeVariable(EditOperation.RemoveVariable(name: "missing")), to: document
            )
        }
        #expect(document.materialize() == before)
    }
}
