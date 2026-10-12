//
//  EditableDocumentPreviewNodesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `EditableDocument.previewNodes(for:)`: the stored nodes property operations would
/// leave, computed without applying them, for an editor's window-local preview.
@MainActor
struct EditableDocumentPreviewNodesTests {
    // MARK: - Fixture

    /// A component with two descendants, an instance of it, and a plain rectangle.
    private func makeDocument() -> EditableDocument {
        let label = PenNode(id: "label", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData()))
        let icon = PenNode(id: "icon", common: PenNodeCommon(name: "Icon"), kind: .rectangle(PenNode.RectangleData()))
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label, icon]))
        )
        let instance = PenNode(id: "ref1", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "comp1")))
        let box = PenNode(
            id: "box",
            common: PenNodeCommon(x: .literal(10), y: .literal(20), opacity: .literal(0.5)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(50)))
        )
        return EditableDocument(from: PenDocument(children: [component, instance, box]))
    }

    /// The node each id names after `operations` are applied to a fresh copy.
    private func committed(_ operations: [EditOperation], ids: Set<String>) throws -> [String: PenNode] {
        let document = makeDocument()
        for operation in operations {
            try document.apply(operation)
        }
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in document.nodes[id].map { (id, $0) } })
    }

    private let setOpacity = EditOperation.setProperties(EditOperation.SetProperties(
        nodeID: "box", properties: ["common.opacity": .double(0.8)]
    ))

    private let setWidth = EditOperation.setProperties(EditOperation.SetProperties(
        nodeID: "box", properties: ["kind.width": .double(240)]
    ))

    private let overrideLabel = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
        refNodeID: "ref1", descendantID: "label", properties: ["name": .string("OK")]
    ))

    private let overrideRootWidth = EditOperation.overrideRoot(EditOperation.OverrideRoot(
        refNodeID: "ref1", properties: ["width": 120]
    ))

    // MARK: - What a commit would store

    @Test("A set previews the node a commit of it would store")
    func setMatchesCommit() throws {
        let preview = try makeDocument().previewNodes(for: [setOpacity])
        #expect(try preview == committed([setOpacity], ids: ["box"]))
    }

    @Test("A descendant override previews the instance a commit of it would store")
    func descendantOverrideMatchesCommit() throws {
        let preview = try makeDocument().previewNodes(for: [overrideLabel])
        #expect(try preview == committed([overrideLabel], ids: ["ref1"]))
    }

    @Test("A root override previews the instance a commit of it would store")
    func rootOverrideMatchesCommit() throws {
        let preview = try makeDocument().previewNodes(for: [overrideRootWidth])
        #expect(try preview == committed([overrideRootWidth], ids: ["ref1"]))
    }

    @Test("Operations on one node fold in order, as a commit applies them")
    func operationsFold() throws {
        let instanceX = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "ref1", properties: ["common.x": .double(40)]
        ))
        let operations = [setOpacity, setWidth, overrideLabel, overrideRootWidth, instanceX]
        let preview = try makeDocument().previewNodes(for: operations)
        #expect(try preview == committed(operations, ids: ["box", "ref1"]))
    }

    // MARK: - Nothing changes

    @Test("Previewing leaves the document, its dirty tracking and its layout invalidation as they were")
    func previewMutatesNothing() throws {
        let document = makeDocument()
        document.clearDirtyNodes()
        let before = document.materialize()
        let invalidation = document.layoutInvalidation
        let preview = try document.previewNodes(for: [setOpacity, setWidth, overrideLabel, overrideRootWidth])
        #expect(Set(preview.keys) == ["box", "ref1"])
        #expect(document.materialize() == before)
        #expect(document.dirtyNodeIDs.isEmpty)
        #expect(document.layoutInvalidation == invalidation)
    }

    // MARK: - Refusals

    @Test("A structural operation is not previewable")
    func structuralThrows() throws {
        let document = makeDocument()
        let before = document.materialize()
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "box"))
        #expect(throws: EditableDocument.PreviewError.notAPropertyEdit("deleteNode")) {
            try document.previewNodes(for: [setOpacity, delete])
        }
        #expect(document.materialize() == before)
    }

    @Test("A set the document would refuse throws the commit's error")
    func refusedSetThrows() throws {
        let bad = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "box", properties: ["kind.nonsense": .double(1)]
        ))
        #expect(throws: EditingError.self) {
            try makeDocument().previewNodes(for: [bad])
        }
    }

    @Test("An override naming nothing in the component throws the commit's error")
    func refusedOverrideThrows() throws {
        let bad = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "missing", properties: ["name": .string("OK")]
        ))
        let document = makeDocument()
        let before = document.materialize()
        #expect(throws: EditingError.self) {
            try document.previewNodes(for: [bad])
        }
        #expect(document.materialize() == before)
    }

    @Test("A set on a node that is gone throws nodeNotFound")
    func missingNodeThrows() throws {
        let gone = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "gone", properties: ["common.opacity": .double(1)]
        ))
        #expect(throws: EditingError.nodeNotFound(id: "gone")) {
            try makeDocument().previewNodes(for: [gone])
        }
    }
}
