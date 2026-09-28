//
//  EditableDocumentSnapshotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditableDocument/materializeSnapshot(isolation:)`` against the synchronous
/// ``EditableDocument/materialize()``.
///
/// The document is made and read in one isolation domain — the test's own — because it
/// is not `Sendable`. That is the contract these tests are written under, and it is why
/// there is no concurrent case here any more: firing a hundred snapshot calls at one
/// document from a task group no longer compiles, which is a stronger answer than the
/// crash test it replaced. `EditingIsolationTests` holds that proof.
struct EditableDocumentSnapshotTests {
    // MARK: - Round-trip equivalence

    @Test("materializeSnapshot produces identical result to materialize for empty document")
    func snapshotEmptyDocument() async {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        let snapshot = await editable.materializeSnapshot()

        #expect(snapshot == editable.materialize())
    }

    @Test("materializeSnapshot produces identical result to materialize for nested document")
    func snapshotNestedDocument() async {
        let child1 = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let child2 = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child1, child2]))
        )
        let topLevel = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [frame, topLevel])
        let editable = EditableDocument(from: doc)

        let snapshot = await editable.materializeSnapshot()

        #expect(snapshot == editable.materialize())
    }

    @Test("materializeSnapshot produces identical result to materialize for document with metadata")
    func snapshotDocumentWithMetadata() async {
        let rect = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(
            version: "2.0",
            themes: ["mode": ["light", "dark"]],
            imports: ["lib": "pencil:components.pen"],
            variables: ["spacing": PenVariable(type: .number, value: .simple(AnyCodable(8)))],
            children: [rect]
        )
        let editable = EditableDocument(from: doc)

        let snapshot = await editable.materializeSnapshot()

        #expect(snapshot == editable.materialize())
    }

    @Test("materializeSnapshot reflects mutations applied after init")
    func snapshotAfterMutation() async throws {
        let rect = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [rect])
        let editable = EditableDocument(from: doc)

        let newNode = PenNode(id: "r2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        try editable.apply(.insertNode(EditOperation.InsertNode(node: newNode, parentID: nil)))

        let snapshot = await editable.materializeSnapshot()

        #expect(snapshot == editable.materialize())
    }

    // MARK: - Repetition

    @Test("repeated materializeSnapshot calls agree")
    func repeatedSnapshotsAgree() async {
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        let doc = PenDocument(children: [frame])
        let editable = EditableDocument(from: doc)

        let first = await editable.materializeSnapshot()
        for _ in 0 ..< 20 {
            #expect(await editable.materializeSnapshot() == first)
        }
    }
}
