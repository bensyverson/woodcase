//
//  EditOperationInverseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationInverseTests {
    // MARK: - Helpers

    /// frame(f1) > [rect(c1), text(c2), ellipse(c3)], frame(f2) > [rect(c4)]
    private func makeTestDoc() -> EditableDocument {
        let c1 = PenNode(id: "c1", common: PenNodeCommon(name: "Child1"), kind: .rectangle(PenNode.RectangleData()))
        let c2 = PenNode(id: "c2", common: PenNodeCommon(name: "Child2"), kind: .text(PenNode.TextData()))
        let c3 = PenNode(id: "c3", common: PenNodeCommon(name: "Child3"), kind: .ellipse(PenNode.EllipseData()))
        let f1 = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame1"),
            kind: .frame(PenNode.FrameData(children: [c1, c2, c3]))
        )
        let c4 = PenNode(id: "c4", common: PenNodeCommon(name: "Child4"), kind: .rectangle(PenNode.RectangleData()))
        let f2 = PenNode(
            id: "f2",
            common: PenNodeCommon(name: "Frame2"),
            kind: .frame(PenNode.FrameData(children: [c4]))
        )
        return EditableDocument(from: PenDocument(children: [f1, f2]))
    }

    /// Document with a reusable component and a ref node pointing to it.
    private func makeRefDoc() -> EditableDocument {
        let innerChild = PenNode(
            id: "inner",
            common: PenNodeCommon(name: "InnerRect"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "MyComponent", reusable: true),
            kind: .frame(PenNode.FrameData(children: [innerChild]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "RefInstance"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let container = PenNode(
            id: "container",
            common: PenNodeCommon(name: "Container"),
            kind: .frame(PenNode.FrameData(children: [refNode]))
        )
        return EditableDocument(from: PenDocument(children: [component, container]))
    }

    private func makeDocWithVariable() -> EditableDocument {
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#ff0000")))
        return EditableDocument(from: PenDocument(
            variables: ["primary": variable],
            children: []
        ))
    }

    // MARK: - Move roundtrip

    @Test("Move roundtrip: move node then undo restores original position")
    func moveRoundtrip() throws {
        let doc = makeTestDoc()
        let moveOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: "f2", index: 0))

        let inverse = try doc.prepareInverse(of: moveOp)
        try doc.apply(moveOp)

        // c1 should now be under f2
        #expect(doc.parentID(of: "c1") == "f2")

        // Apply inverse to undo
        for op in inverse {
            try doc.apply(op)
        }

        // c1 should be back under f1 at index 0
        #expect(doc.parentID(of: "c1") == "f1")
        #expect(doc.childIDs(of: "f1").first == "c1")
    }

    // MARK: - Insert/delete roundtrip

    @Test("Insert roundtrip: insert then undo removes the node")
    func insertRoundtrip() throws {
        let doc = makeTestDoc()
        let newNode = PenNode(id: "new1", common: PenNodeCommon(name: "New"), kind: .rectangle(PenNode.RectangleData()))
        let insertOp = EditOperation.insertNode(EditOperation.InsertNode(node: newNode, parentID: "f1", index: 1))

        let inverse = try doc.prepareInverse(of: insertOp)
        try doc.apply(insertOp)

        #expect(doc.nodes["new1"] != nil)

        for op in inverse {
            try doc.apply(op)
        }

        #expect(doc.nodes["new1"] == nil)
    }

    // MARK: - Delete/insert roundtrip

    @Test("Delete roundtrip: delete subtree then undo restores it with all children")
    func deleteRoundtrip() throws {
        let doc = makeTestDoc()
        let deleteOp = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "f1"))

        let inverse = try doc.prepareInverse(of: deleteOp)
        try doc.apply(deleteOp)

        // f1 and its children should be gone
        #expect(doc.nodes["f1"] == nil)
        #expect(doc.nodes["c1"] == nil)

        for op in inverse {
            try doc.apply(op)
        }

        // f1 should be back at root with all children
        #expect(doc.nodes["f1"] != nil)
        #expect(doc.nodes["c1"] != nil)
        #expect(doc.nodes["c2"] != nil)
        #expect(doc.nodes["c3"] != nil)
        #expect(doc.childIDs(of: "f1") == ["c1", "c2", "c3"])
        #expect(doc.rootOrder.first == "f1")
    }

    // MARK: - UpdateCommon roundtrip

    @Test("UpdateCommon roundtrip: update name then undo restores old name")
    func updateCommonRoundtrip() throws {
        let doc = makeTestDoc()
        var newCommon = PenNodeCommon(name: "Renamed")
        newCommon.opacity = .literal(0.5)
        let updateOp = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: newCommon))

        let inverse = try doc.prepareInverse(of: updateOp)
        try doc.apply(updateOp)

        #expect(doc.nodes["c1"]?.common.name == "Renamed")

        for op in inverse {
            try doc.apply(op)
        }

        #expect(doc.nodes["c1"]?.common.name == "Child1")
        #expect(doc.nodes["c1"]?.common.opacity == nil)
    }

    // MARK: - UpdateKind roundtrip

    @Test("UpdateKind roundtrip: update kind then undo restores old kind")
    func updateKindRoundtrip() throws {
        let doc = makeTestDoc()
        let newKind = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(200),
            height: .fixed(100)
        ))
        let updateOp = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "c1", kind: newKind))

        let inverse = try doc.prepareInverse(of: updateOp)
        try doc.apply(updateOp)

        if case let .rectangle(data) = doc.nodes["c1"]?.kind {
            #expect(data.width == .fixed(200))
        } else {
            Issue.record("Expected rectangle kind")
        }

        for op in inverse {
            try doc.apply(op)
        }

        // Original rectangle had no width/height
        if case let .rectangle(data) = doc.nodes["c1"]?.kind {
            #expect(data.width == nil)
        } else {
            Issue.record("Expected rectangle kind after undo")
        }
    }

    // MARK: - Variable roundtrips

    @Test("Add variable roundtrip: add then undo removes it")
    func addVariableRoundtrip() throws {
        let doc = EditableDocument(from: PenDocument(children: []))
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        let addOp = EditOperation.addVariable(EditOperation.AddVariable(name: "accent", variable: variable))

        let inverse = try doc.prepareInverse(of: addOp)
        try doc.apply(addOp)

        #expect(doc.variables?["accent"] != nil)

        for op in inverse {
            try doc.apply(op)
        }

        #expect(doc.variables?["accent"] == nil)
    }

    @Test("Update variable roundtrip: update then undo restores old value")
    func updateVariableRoundtrip() throws {
        let doc = makeDocWithVariable()
        let newVar = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        let updateOp = EditOperation.updateVariable(EditOperation.UpdateVariable(name: "primary", variable: newVar))

        let inverse = try doc.prepareInverse(of: updateOp)
        try doc.apply(updateOp)

        #expect(doc.variables?["primary"]?.value == .simple(AnyCodable("#00ff00")))

        for op in inverse {
            try doc.apply(op)
        }

        #expect(doc.variables?["primary"]?.value == .simple(AnyCodable("#ff0000")))
    }

    // MARK: - Move to/from root

    @Test("Move to root roundtrip: move child to root then undo restores parent")
    func moveToRootRoundtrip() throws {
        let doc = makeTestDoc()
        let moveOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: nil))

        let inverse = try doc.prepareInverse(of: moveOp)
        try doc.apply(moveOp)

        #expect(doc.parentID(of: "c1") == nil)
        #expect(doc.rootOrder.contains("c1"))

        for op in inverse {
            try doc.apply(op)
        }

        #expect(doc.parentID(of: "c1") == "f1")
        #expect(doc.childIDs(of: "f1").first == "c1")
    }

    @Test("Move from root roundtrip: move root node into parent then undo")
    func moveFromRootRoundtrip() throws {
        let doc = makeTestDoc()
        let moveOp = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "f2", newParentID: "f1"))

        let inverse = try doc.prepareInverse(of: moveOp)
        try doc.apply(moveOp)

        #expect(doc.parentID(of: "f2") == "f1")

        for op in inverse {
            try doc.apply(op)
        }

        #expect(doc.parentID(of: "f2") == nil)
        #expect(doc.rootOrder == ["f1", "f2"])
    }

    // MARK: - DetachRef roundtrip

    @Test("DetachRef roundtrip: detach ref then undo restores original ref node")
    func detachRefRoundtrip() throws {
        let doc = makeRefDoc()
        let detachParam = EditOperation.DetachRef(refNodeID: "ref1")
        let detachOp = EditOperation.detachRef(detachParam)

        // Phase 1: capture partial inverse (insert-ref) before detach
        let partialInverse = try doc.prepareInverse(of: detachOp)

        // Phase 2: apply detach and get the expanded root ID
        let result = try doc.detachRef(detachParam)

        // Phase 3: complete the inverse with the expanded root ID
        let fullInverse = doc.completeDetachInverse(
            expandedRootID: result.rootNodeID,
            partialInverse: partialInverse
        )

        // ref1 should be gone (replaced by expanded nodes)
        #expect(doc.nodes["ref1"] == nil)
        #expect(fullInverse.count == 2)

        // Apply full inverse to undo
        for op in fullInverse {
            try doc.apply(op)
        }

        // ref1 should be restored under container
        #expect(doc.nodes["ref1"] != nil)
        #expect(doc.parentID(of: "ref1") == "container")
        if case .ref = doc.nodes["ref1"]?.kind {
            // Good — it's a ref again
        } else {
            Issue.record("Expected ref kind after undo")
        }
    }

    // MARK: - Array length checks

    @Test("Most operations return single-element inverse array")
    func singleElementInverse() throws {
        let doc = makeTestDoc()

        let moveInverse = try doc.prepareInverse(of: .moveNode(
            EditOperation.MoveNode(nodeID: "c1", newParentID: "f2")
        ))
        #expect(moveInverse.count == 1)

        let insertInverse = try doc.prepareInverse(of: .insertNode(
            EditOperation.InsertNode(
                node: PenNode(id: "tmp", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData())),
                parentID: "f1"
            )
        ))
        #expect(insertInverse.count == 1)

        let deleteInverse = try doc.prepareInverse(of: .deleteNode(
            EditOperation.DeleteNode(nodeID: "c1")
        ))
        #expect(deleteInverse.count == 1)

        let commonInverse = try doc.prepareInverse(of: .updateCommon(
            EditOperation.UpdateCommon(nodeID: "c1", common: PenNodeCommon(name: "X"))
        ))
        #expect(commonInverse.count == 1)
    }

    @Test("DetachRef partial inverse returns single element, completed inverse returns two")
    func detachRefInverseElementCounts() throws {
        let doc = makeRefDoc()
        let detachParam = EditOperation.DetachRef(refNodeID: "ref1")

        let partialInverse = try doc.prepareInverse(of: .detachRef(detachParam))
        #expect(partialInverse.count == 1)

        let result = try doc.detachRef(detachParam)
        let fullInverse = doc.completeDetachInverse(
            expandedRootID: result.rootNodeID,
            partialInverse: partialInverse
        )
        #expect(fullInverse.count == 2)
    }
}
