//
//  EditOperationOverrideTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationOverrideTests {
    // MARK: - Helpers

    private func makeRefDoc() -> EditableDocument {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        // A second overridable descendant: the override guard refuses keys that
        // name nothing in the component, so the "different descendant" case needs
        // a real one.
        let icon = PenNode(
            id: "icon",
            common: PenNodeCommon(name: "Icon"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label, icon]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let doc = PenDocument(children: [component, refNode])
        return EditableDocument(from: doc)
    }

    // MARK: - Basic Override

    @Test("Override with no existing overrides creates descendants")
    func overrideCreatesDescendants() throws {
        let editable = makeRefDoc()

        try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        guard case let .ref(refData) = editable.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["label"] != nil)
        #expect(refData.descendants?["label"]?.properties["name"] == .string("OK"))
    }

    @Test("Override on different descendant merges into existing descendants")
    func overrideMergesDifferentDescendant() throws {
        let editable = makeRefDoc()

        // First override on "label"
        try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        // Second override on different descendant "icon"
        try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "icon",
            properties: ["name": .string("check")]
        )))

        guard case let .ref(refData) = editable.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["label"]?.properties["name"] == .string("OK"))
        #expect(refData.descendants?["icon"]?.properties["name"] == .string("check"))
    }

    @Test("Override same descendant updates properties")
    func overrideSameDescendantUpdates() throws {
        let editable = makeRefDoc()

        try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("Cancel"), "opacity": .double(0.5)]
        )))

        guard case let .ref(refData) = editable.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["label"]?.properties["name"] == .string("Cancel"))
        #expect(refData.descendants?["label"]?.properties["opacity"] == .double(0.5))
    }

    @Test("Override throws for non-existent node")
    func overrideThrowsNodeNotFound() {
        let editable = makeRefDoc()
        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "missing",
                descendantID: "label",
                properties: ["name": .string("OK")]
            )))
        }
    }

    @Test("Override throws for non-ref node")
    func overrideThrowsNotRef() {
        let rect = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [rect])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.notARefNode(id: "r1")) {
            try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "r1",
                descendantID: "label",
                properties: ["name": .string("OK")]
            )))
        }
    }

    @Test("Override invalidates expansion cache")
    func overrideInvalidatesCache() throws {
        let editable = makeRefDoc()

        // Warm the cache
        _ = try editable.expandRef(nodeID: "ref1")
        #expect(editable.expansionCache?.entries["ref1"] != nil)

        try editable.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        #expect(editable.expansionCache?.entries["ref1"] == nil)
    }

    // MARK: - Codable round-trip

    @Test("OverrideDescendant operation round-trips through Codable")
    func overrideCodableRoundTrip() throws {
        let op = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        ))

        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)

        #expect(op == decoded)
    }
}
