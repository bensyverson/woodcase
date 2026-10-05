//
//  ComponentLoopGuardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Every edit that would make components contain each other is refused, naming the loop
/// it would close, and leaves the document as it was; every other edit goes through.
@MainActor
struct ComponentLoopGuardTests {
    // MARK: - Helpers

    /// `CmpA` holds an instance of `CmpB` (`AB`); `CmpB` holds a box and an instance of
    /// `CmpC` (`BC`); `Hold` is a plain frame holding an instance of `CmpA`, and `CmpA`
    /// also names `Hold` and the missing `New` (refs that place nothing yet).
    private static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "CmpA", "type": "frame", "reusable": true, "children": [
            {"id": "TA", "type": "text", "content": "a"},
            {"id": "AB", "type": "ref", "ref": "CmpB"},
            {"id": "AHold", "type": "ref", "ref": "Hold"},
            {"id": "ANew", "type": "ref", "ref": "New"}
          ]},
          {"id": "CmpB", "type": "frame", "reusable": true, "children": [
            {"id": "TB", "type": "text", "content": "b"},
            {"id": "BBox", "type": "frame", "children": []},
            {"id": "BC", "type": "ref", "ref": "CmpC"}
          ]},
          {"id": "CmpC", "type": "frame", "reusable": true, "children": [
            {"id": "TC", "type": "text", "content": "c"}
          ]},
          {"id": "Hold", "type": "frame", "children": [
            {"id": "HoldA", "type": "ref", "ref": "CmpA"}
          ]},
          {"id": "Page", "type": "frame", "children": [
            {"id": "PA", "type": "ref", "ref": "CmpA"}
          ]}
        ]}
        """#))
    }

    private static func ref(_ id: String, to target: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: target)))
    }

    /// Applies `operation` and expects the loop error with `path`, the document unchanged.
    private static func expectRefused(
        _ operation: EditOperation,
        path: [String],
        in document: EditableDocument,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let before = document.materialize()
        #expect(throws: EditingError.wouldCloseComponentLoop(path: path), sourceLocation: sourceLocation) {
            try document.apply(operation)
        }
        #expect(throws: EditingError.wouldCloseComponentLoop(path: path), sourceLocation: sourceLocation) {
            try document.validate(operation)
        }
        #expect(document.materialize() == before, sourceLocation: sourceLocation)
        #expect(document.componentLoops.isEmpty, sourceLocation: sourceLocation)
    }

    // MARK: - Structure

    @Test("Inserting an instance of a component into one it renders is refused, naming the loop")
    func insertClosingLoopIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .insertNode(EditOperation.InsertNode(node: Self.ref("BA", to: "CmpA"), parentID: "BBox")),
            path: ["CmpB", "CmpA", "CmpB"], in: document
        )
    }

    @Test("Inserting an instance of a component into itself is refused")
    func insertSelfIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .insertNode(EditOperation.InsertNode(node: Self.ref("BB", to: "CmpB"), parentID: "CmpB")),
            path: ["CmpB", "CmpB"], in: document
        )
    }

    @Test("Inserting an instance that closes no loop goes through")
    func insertOpenIsAllowed() throws {
        let document = try Self.document()
        try document.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("BC2", to: "CmpC"), parentID: "CmpB")))
        try document.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("PB", to: "CmpB"), parentID: "Page")))
        #expect(document.nodes["BC2"] != nil && document.nodes["PB"] != nil)
    }

    @Test("Inserting a component whose instance a loop member already names is refused")
    func insertComponentClosingDanglingRefIsRefused() throws {
        let document = try Self.document()
        let new = PenNode(
            id: "New", common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [Self.ref("NewA", to: "CmpA")]))
        )
        Self.expectRefused(.insertNode(EditOperation.InsertNode(node: new)), path: ["New", "CmpA", "New"], in: document)
    }

    @Test("Moving an instance into a component it renders is refused")
    func moveClosingLoopIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .moveNode(EditOperation.MoveNode(nodeID: "PA", newParentID: "BBox")),
            path: ["CmpB", "CmpA", "CmpB"], in: document
        )
    }

    @Test("Moving an instance within its component goes through")
    func moveWithinIsAllowed() throws {
        let document = try Self.document()
        try document.apply(.moveNode(EditOperation.MoveNode(nodeID: "BC", newParentID: "BBox")))
        #expect(document.parents["BC"] == "BBox")
    }

    @Test("Replacing a node with an instance that closes a loop is refused")
    func replaceClosingLoopIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .replaceSubtree(EditOperation.ReplaceSubtree(node: Self.ref("BC", to: "CmpA"))),
            path: ["CmpB", "CmpA", "CmpB"], in: document
        )
    }

    // MARK: - Content

    @Test("Retargeting a nested instance at a component that renders its own is refused")
    func retargetIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .setProperties(EditOperation.SetProperties(nodeID: "BC", properties: ["kind.ref": "CmpA"])),
            path: ["CmpB", "CmpA", "CmpB"], in: document
        )
        Self.expectRefused(
            .updateKind(EditOperation.UpdateKind(nodeID: "BC", kind: .ref(PenNode.RefData(ref: "CmpA")))),
            path: ["CmpB", "CmpA", "CmpB"], in: document
        )
    }

    @Test("Making a frame reusable whose instance a member names, while it holds that member, is refused")
    func makingReusableIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .setProperties(EditOperation.SetProperties(nodeID: "Hold", properties: ["common.reusable": true])),
            path: ["Hold", "CmpA", "Hold"], in: document
        )
        let hold = try #require(document.nodes["Hold"])
        var common = hold.common
        common.reusable = true
        Self.expectRefused(
            .updateCommon(EditOperation.UpdateCommon(nodeID: "Hold", common: common)),
            path: ["Hold", "CmpA", "Hold"], in: document
        )
    }

    @Test("An override that repoints a nested instance into a loop is refused")
    func repointingOverrideIsRefused() throws {
        let document = try Self.document()
        Self.expectRefused(
            .overrideDescendant(EditOperation.OverrideDescendant(refNodeID: "AB", descendantID: "BC", properties: ["ref": "CmpA"])),
            path: ["CmpA", "CmpA"], in: document
        )
    }

    @Test("Slot content holding an instance that closes a loop is refused")
    func slotContentIsRefused() throws {
        let document = try Self.document()
        let content: AnyCodable = .array([.dictionary(["id": "Slotted", "type": "ref", "ref": "CmpA"])])
        Self.expectRefused(
            .overrideDescendant(EditOperation.OverrideDescendant(refNodeID: "AB", descendantID: "BBox", properties: ["children": content])),
            path: ["CmpA", "CmpA"], in: document
        )
        Self.expectRefused(
            .overrideRoot(EditOperation.OverrideRoot(refNodeID: "AB", properties: ["children": content])),
            path: ["CmpA", "CmpA"], in: document
        )
    }

    // MARK: - Documents that arrive with a loop

    @Test("A document that arrives with a loop takes edits that close no new one, and the fix")
    func loopyDocumentTakesOtherEdits() throws {
        let document = try EditableDocument(from: ComponentLoopReadTests.loopy())
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "TA", properties: ["kind.content": "x"])))
        try document.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("PB", to: "CmpB"), parentID: "Page")))
        #expect(throws: EditingError.wouldCloseComponentLoop(path: ["CmpB", "CmpD", "CmpB"])) {
            try document.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("BD", to: "CmpD"), parentID: "CmpB")))
        }
        // Another edge inside the loop it already has closes nothing new.
        try document.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("AA", to: "CmpA"), parentID: "CmpA")))
        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "AA")))
        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "BinA")))
        #expect(document.componentLoops.map(\.ids) == [["CmpS"]])
    }

    @Test("A session's undo of a loop's fix restores the file as it arrived")
    func sessionUndoRestoresLoop() throws {
        let session = try DocumentSession(
            document: ComponentLoopReadTests.loopy(),
            author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")),
            collaborative: false
        )
        let before = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [.deleteNode(EditOperation.DeleteNode(nodeID: "BinA"))])))
        #expect(session.document.componentLoops.count == 1)
        try session.submit(.undo)
        #expect(session.document.materialize() == before)
    }

    @Test("A session refuses a local edit that closes a loop, and keeps the document")
    func sessionRefusesLoop() throws {
        let session = try DocumentSession(
            document: Self.document().materialize(),
            author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")),
            collaborative: true
        )
        let before = session.document.materialize()
        #expect(throws: EditingError.wouldCloseComponentLoop(path: ["CmpB", "CmpA", "CmpB"])) {
            try session.submit(.local(LocalEdit(operations: [
                .insertNode(EditOperation.InsertNode(node: Self.ref("BC9", to: "CmpC"), parentID: "CmpB")),
                .insertNode(EditOperation.InsertNode(node: Self.ref("BA", to: "CmpA"), parentID: "CmpB")),
            ])))
        }
        #expect(session.document.materialize() == before)
    }
}

/// The guard reads nothing for an edit that cannot add a component edge.
@MainActor
struct ComponentLoopGuardCostTests {
    @Test("A nudge, a fill and a plain insert, on a page or in a component, build no overlay")
    func plainEditsSkipTheGuard() throws {
        let document = try EditableDocument(from: ComponentLoopReadTests.loopy())
        let rect = PenNode(id: "R9", common: PenNodeCommon(name: "R9"), kind: .rectangle(PenNode.RectangleData()))
        let edits: [EditOperation] = [
            .setProperties(EditOperation.SetProperties(nodeID: "TA", properties: ["common.x": 4, "kind.content": "x"])),
            .insertNode(EditOperation.InsertNode(node: rect, parentID: "CmpA")),
            .insertNode(EditOperation.InsertNode(node: rect, parentID: "Page")),
            .moveNode(EditOperation.MoveNode(nodeID: "TA", newParentID: "CmpB")),
        ]
        for edit in edits {
            #expect(!document.canAddComponentEdge(edit), "\(edit)")
            #expect(document.componentGraphEdit(for: edit) == nil, "\(edit)")
        }
    }
}
