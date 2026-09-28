//
//  EditOperationPropertyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationPropertyTests {
    // MARK: - Helpers

    private func makeDocWithRect() -> EditableDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Original", opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData())
        )
        return EditableDocument(from: PenDocument(children: [rect]))
    }

    // MARK: - updateCommon

    @Test("updateCommon changes opacity on a node")
    func updateCommonOpacity() throws {
        let editable = makeDocWithRect()
        let newCommon = PenNodeCommon(name: "Updated", opacity: .literal(0.5))

        try editable.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "r1", common: newCommon)))

        let node = editable.node(id: "r1")
        #expect(node?.common.name == "Updated")
        #expect(node?.common.opacity == .literal(0.5))
    }

    @Test("updateCommon rejects unknown node ID")
    func updateCommonUnknown() throws {
        let editable = makeDocWithRect()
        let common = PenNodeCommon()

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "missing", common: common)))
        }
    }

    // MARK: - updateKind

    @Test("updateKind changes rectangle fill")
    func updateKindFill() throws {
        let editable = makeDocWithRect()
        let newKind = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(200)
        ))

        try editable.apply(.updateKind(EditOperation.UpdateKind(nodeID: "r1", kind: newKind)))

        if case let .rectangle(data) = editable.node(id: "r1")?.kind {
            #expect(data.width == .fixed(200))
        } else {
            Issue.record("Expected rectangle kind")
        }
    }

    @Test("updateKind strips children from provided kind")
    func updateKindStripsChildren() throws {
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [child]))
        )
        let editable = EditableDocument(from: PenDocument(children: [frame]))

        // Provide a kind with children — they should be stripped
        let newKind = PenNode.Kind.frame(PenNode.FrameData(
            layout: .horizontal,
            children: [PenNode(id: "bogus", common: PenNodeCommon(), kind: .text(PenNode.TextData()))]
        ))

        try editable.apply(.updateKind(EditOperation.UpdateKind(nodeID: "f1", kind: newKind)))

        if case let .frame(data) = editable.node(id: "f1")?.kind {
            #expect(data.children == nil)
            #expect(data.layout == .horizontal)
        } else {
            Issue.record("Expected frame kind")
        }
        // Structure preserved
        #expect(editable.childIDs(of: "f1") == ["c1"])
    }

    @Test("updateKind rejects unknown node ID")
    func updateKindUnknown() throws {
        let editable = makeDocWithRect()
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData())

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(.updateKind(EditOperation.UpdateKind(nodeID: "missing", kind: kind)))
        }
    }
}
