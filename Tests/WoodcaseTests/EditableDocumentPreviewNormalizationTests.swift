//
//  EditableDocumentPreviewNormalizationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `EditableDocument.previewNodes(for:)` normalizes each operation as a commit does
/// (``EditOperation/normalized(in:)``), so a preview and a commit cannot disagree about
/// a deep metadata key, a whole-struct write or the operation before it.
@MainActor
struct EditableDocumentPreviewNormalizationTests {
    // MARK: - Fixture

    private func makeDocument() throws -> EditableDocument {
        let box = PenNode(
            id: "box",
            common: PenNodeCommon(x: .literal(10), opacity: .literal(0.5)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(50)))
        )
        let note = PenNode(id: "note", common: PenNodeCommon(name: "Note"), kind: .text(PenNode.TextData()))
        let frame = PenNode(id: "frame", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: [])))
        let document = EditableDocument(from: PenDocument(children: [box, note, frame]))
        // A node that already carries metadata, so a deep key must keep what is there.
        let seed = set("note", ["common.metadata.woodcase.role": .string("note")])
        try document.apply(seed.normalized(in: document))
        return document
    }

    private func set(_ id: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: id, properties: properties))
    }

    /// The node each id holds after committing `operations` through a session-style
    /// normalization, the way `DocumentSession` applies them.
    private func committed(_ operations: [EditOperation], ids: Set<String>) throws -> [String: PenNode] {
        let document = try makeDocument()
        for operation in operations {
            try document.apply(operation.normalized(in: document))
        }
        return Dictionary(uniqueKeysWithValues: ids.compactMap { id in document.nodes[id].map { (id, $0) } })
    }

    private func expectSameAsCommit(_ operations: [EditOperation], ids: Set<String>) throws {
        let preview = try makeDocument().previewNodes(for: operations)
        #expect(Set(preview.keys) == ids)
        #expect(try preview == committed(operations, ids: ids))
    }

    // MARK: - Deep metadata keys (setProperties)

    @Test("A deep metadata key previews the node a commit of it stores")
    func deepKeyMatchesCommit() throws {
        let op = set("box", ["common.metadata.woodcase.fontSize": .double(18)])
        try expectSameAsCommit([op], ids: ["box"])
        let preview = try makeDocument().previewNodes(for: [op])
        #expect(preview["box"]?.common.metadata != nil)
    }

    @Test("A deep key keeps the metadata entries already on the node")
    func deepKeyKeepsSiblings() throws {
        let op = set("note", ["common.metadata.woodcase.fontSize": .double(18)])
        try expectSameAsCommit([op], ids: ["note"])
        let preview = try makeDocument().previewNodes(for: [op])
        let extensions = preview["note"]?.common.metadata?.extensions ?? [:]
        #expect(extensions["woodcase"] != nil)
    }

    @Test("Two deep keys on one node fold in order, each against what the first left")
    func deepKeysFoldInOrder() throws {
        let first = set("box", ["common.metadata.woodcase.fontSize": .double(18)])
        let second = set("box", ["common.metadata.woodcase.role": .string("title")])
        try expectSameAsCommit([first, second], ids: ["box"])
        let preview = try makeDocument().previewNodes(for: [first, second])
        let encoded = try String(decoding: JSONEncoder().encode(preview["box"]), as: UTF8.self)
        #expect(encoded.contains("fontSize") && encoded.contains("title"))
    }

    @Test("A deep key mixed with ordinary keys previews as a commit stores it")
    func deepKeyMixedWithOrdinary() throws {
        let op = set("box", ["common.opacity": .double(0.8), "common.metadata.woodcase.fontSize": .double(12)])
        try expectSameAsCommit([op], ids: ["box"])
    }

    @Test("A deep key on a node that is gone throws nodeNotFound")
    func deepKeyMissingNode() throws {
        let op = set("gone", ["common.metadata.woodcase.fontSize": .double(18)])
        #expect(throws: EditingError.nodeNotFound(id: "gone")) {
            try makeDocument().previewNodes(for: [op])
        }
    }

    @Test("A set without a deep key is unchanged by normalizing")
    func plainSetUnchanged() throws {
        try expectSameAsCommit([set("box", ["common.opacity": .double(0.2)])], ids: ["box"])
    }

    // MARK: - Whole-struct writes

    @Test("A whole-struct updateCommon previews as the patch a commit normalizes it to")
    func updateCommonMatchesCommit() throws {
        var common = try #require(makeDocument().nodes["box"]?.common)
        common.name = "Renamed"
        common.opacity = .literal(0.25)
        let op = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "box", common: common))
        try expectSameAsCommit([op], ids: ["box"])
        let preview = try makeDocument().previewNodes(for: [op])
        #expect(preview["box"]?.common.name == "Renamed")
    }

    @Test("A same-type updateKind previews as the patch a commit normalizes it to")
    func updateKindMatchesCommit() throws {
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData(width: .fixed(300), height: .fixed(50)))
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "box", kind: kind))
        try expectSameAsCommit([op], ids: ["box"])
    }

    @Test("A whole-struct write sees what an earlier operation in the batch left")
    func wholeStructAfterEarlierOperation() throws {
        let first = set("box", ["common.opacity": .double(0.9)])
        var common = try #require(makeDocument().nodes["box"]?.common)
        common.opacity = .literal(0.9)
        common.name = "Renamed"
        let second = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "box", common: common))
        try expectSameAsCommit([first, second], ids: ["box"])
    }

    @Test("An updateKind that changes the node's type has no property form and is not previewable")
    func retypeNotPreviewable() throws {
        let kind = PenNode.Kind.ellipse(PenNode.EllipseData())
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "box", kind: kind))
        #expect(throws: EditableDocument.PreviewError.notAPropertyEdit("updateKind")) {
            try makeDocument().previewNodes(for: [op])
        }
    }

    @Test("An updateKind that only changes whether an empty container declares its children is not previewable")
    func declaredNessNotPreviewable() throws {
        let document = try makeDocument()
        let kind = try #require(document.nodes["frame"]?.kind)
        let flipped: EditOperation.UpdateKind.EmptyChildren = document.children["frame"] == nil ? .declared : .absent
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "frame", kind: kind, emptyChildren: flipped))
        #expect(throws: EditableDocument.PreviewError.notAPropertyEdit("updateKind")) {
            try document.previewNodes(for: [op])
        }
    }

    @Test("An updateCommon on a node that is gone is not previewable")
    func updateCommonMissingNode() throws {
        let op = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "gone", common: PenNodeCommon()))
        #expect(throws: EditableDocument.PreviewError.notAPropertyEdit("updateCommon")) {
            try makeDocument().previewNodes(for: [op])
        }
    }

    // MARK: - Operations normalization leaves alone

    @Test("A structural operation is still refused with its own case name")
    func structuralStillRefused() throws {
        let op = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "box"))
        #expect(throws: EditableDocument.PreviewError.notAPropertyEdit("deleteNode")) {
            try makeDocument().previewNodes(for: [op])
        }
    }

    // MARK: - Nothing changes

    @Test("Previewing a deep key leaves the document as it was")
    func previewMutatesNothing() throws {
        let document = try makeDocument()
        document.clearDirtyNodes()
        let before = document.materialize()
        _ = try document.previewNodes(for: [set("box", ["common.metadata.woodcase.fontSize": .double(18)])])
        #expect(document.materialize() == before)
        #expect(document.dirtyNodeIDs.isEmpty)
    }
}
