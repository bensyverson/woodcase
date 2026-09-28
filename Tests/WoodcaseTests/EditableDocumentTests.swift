//
//  EditableDocumentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentTests {
    // MARK: - Init from PenDocument (flatten)

    @Test("Init from empty document")
    func initEmpty() {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        #expect(editable.nodes.isEmpty)
        #expect(editable.rootOrder.isEmpty)
        #expect(editable.children.isEmpty)
        #expect(editable.parents.isEmpty)
    }

    @Test("Init from flat document with 3 top-level rectangles")
    func initFlat() {
        let r1 = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let r2 = PenNode(id: "r2", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let r3 = PenNode(id: "r3", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [r1, r2, r3])
        let editable = EditableDocument(from: doc)

        #expect(editable.nodes.count == 3)
        #expect(editable.rootOrder == ["r1", "r2", "r3"])
        // Leaves have no children entries
        #expect(editable.children.isEmpty)
        #expect(editable.parents.isEmpty)
    }

    @Test("Init from nested document (frame with children)")
    func initNested() {
        let child1 = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let child2 = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child1, child2]))
        )
        let doc = PenDocument(children: [frame])
        let editable = EditableDocument(from: doc)

        #expect(editable.nodes.count == 3)
        #expect(editable.rootOrder == ["f1"])
        // Frame stored with nil children
        if case let .frame(data) = editable.nodes["f1"]?.kind {
            #expect(data.children == nil)
        } else {
            Issue.record("Expected frame kind for f1")
        }
        // Children map
        #expect(editable.children["f1"] == ["c1", "c2"])
        // Parent map
        #expect(editable.parents["c1"] == "f1")
        #expect(editable.parents["c2"] == "f1")
    }

    @Test("Init from deeply nested tree (frame > frame > text)")
    func initDeepNest() {
        let text = PenNode(id: "t1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let innerFrame = PenNode(
            id: "f2",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [text]))
        )
        let outerFrame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [innerFrame]))
        )
        let doc = PenDocument(children: [outerFrame])
        let editable = EditableDocument(from: doc)

        #expect(editable.nodes.count == 3)
        #expect(editable.rootOrder == ["f1"])
        #expect(editable.children["f1"] == ["f2"])
        #expect(editable.children["f2"] == ["t1"])
        #expect(editable.parents["f2"] == "f1")
        #expect(editable.parents["t1"] == "f2")
    }

    // MARK: - Materialize round-trip

    @Test("Materialize round-trip: empty document")
    func roundTripEmpty() {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)
        let result = editable.materialize()

        #expect(result == doc)
    }

    @Test("Materialize round-trip: flat document")
    func roundTripFlat() {
        let r1 = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let r2 = PenNode(id: "r2", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [r1, r2])
        let editable = EditableDocument(from: doc)
        let result = editable.materialize()

        #expect(result == doc)
    }

    @Test("Materialize round-trip: nested document")
    func roundTripNested() {
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        let doc = PenDocument(children: [frame])
        let editable = EditableDocument(from: doc)
        let result = editable.materialize()

        #expect(result == doc)
    }

    @Test("Materialize round-trip: deeply nested")
    func roundTripDeep() {
        let text = PenNode(id: "t1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let inner = PenNode(
            id: "f2",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [text]))
        )
        let outer = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [inner]))
        )
        let doc = PenDocument(children: [outer])
        let editable = EditableDocument(from: doc)
        let result = editable.materialize()

        #expect(result == doc)
    }

    @Test("Materialize preserves document metadata")
    func roundTripMetadata() {
        let doc = PenDocument(
            version: "2.9",
            themes: ["mode": ["light", "dark"]],
            imports: ["icons": "icons.pen"],
            variables: ["primary": PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))],
            children: []
        )
        let editable = EditableDocument(from: doc)
        let result = editable.materialize()

        #expect(result.version == "2.9")
        #expect(result.themes == ["mode": ["light", "dark"]])
        #expect(result.imports == ["icons": "icons.pen"])
        #expect(result.variables?["primary"]?.type == .color)
    }

    // MARK: - materializeSubtree

    @Test("materializeSubtree returns reconstructed subtree")
    func materializeSubtree() throws {
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        let doc = PenDocument(children: [frame])
        let editable = EditableDocument(from: doc)

        let subtree = try editable.materializeSubtree(rootID: "f1")
        #expect(subtree == frame)
    }

    @Test("materializeSubtree throws for unknown ID")
    func materializeSubtreeUnknown() throws {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.materializeSubtree(rootID: "missing")
        }
    }

    // MARK: - Group support

    @Test("Materialize round-trip: group with children")
    func roundTripGroup() {
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .ellipse(PenNode.EllipseData()))
        let group = PenNode(
            id: "g1",
            common: PenNodeCommon(),
            kind: .group(PenNode.GroupData(children: [child]))
        )
        let doc = PenDocument(children: [group])
        let editable = EditableDocument(from: doc)
        let result = editable.materialize()

        #expect(result == doc)
    }
}
