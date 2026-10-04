//
//  GranularInverseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `granularInverse(of:)` splits an undo into guarded, per-key steps that land by anchor.
struct GranularInverseTests {
    /// Captures the steps, applies the forward op, then the steps in order.
    private func roundTrip(_ operation: EditOperation, in document: EditableDocument) throws -> [GuardedInverse] {
        let steps = try document.granularInverse(of: operation)
        try document.apply(operation)
        for step in steps {
            try document.apply(step.resolved(in: document))
        }
        return steps
    }

    private func foreignInsert(_ id: String, into parentID: String?, at index: Int, in document: EditableDocument) throws {
        let node = PenNode(id: id, common: PenNodeCommon(name: id), kind: .rectangle(PenNode.RectangleData()))
        try document.apply(.insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: index)))
    }

    // MARK: - Placement

    @Test("a move inverse anchored on a sibling lands after it despite a foreign insert before it")
    func moveAnchoredAfterForeignInsert() throws {
        let document = SessionTestDocuments.make()
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0))
        let steps = try document.granularInverse(of: move)
        try document.apply(move)
        try foreignInsert("x", into: "f1", at: 0, in: document)

        #expect(steps.count == 1)
        #expect(steps.first?.keys == [.placement(node: "c2")])
        for step in steps {
            try document.apply(step.resolved(in: document))
        }
        #expect(document.childIDs(of: "f1") == ["x", "c1", "c2", "c3"])
        #expect(document.childIDs(of: "f2") == ["c4"])
    }

    @Test("a delete inverse re-inserts after its anchor despite a foreign insert before it")
    func deleteAnchoredAfterForeignInsert() throws {
        let document = SessionTestDocuments.make()
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "c3"))
        let steps = try document.granularInverse(of: delete)
        try document.apply(delete)
        try foreignInsert("x", into: "f1", at: 0, in: document)
        for step in steps {
            try document.apply(step.resolved(in: document))
        }
        #expect(document.childIDs(of: "f1") == ["x", "c1", "c2", "c3"])
    }

    @Test("a first child lands first again")
    func firstChildLandsFirst() throws {
        let document = SessionTestDocuments.make()
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: "f2"))
        let steps = try document.granularInverse(of: move)
        try document.apply(move)
        try foreignInsert("x", into: "f1", at: 1, in: document)
        for step in steps {
            try document.apply(step.resolved(in: document))
        }
        #expect(document.childIDs(of: "f1") == ["c1", "c2", "x", "c3"])
    }

    @Test("with its anchor gone, a step falls back to the captured index, clamped")
    func anchorGoneFallsBack() throws {
        let document = SessionTestDocuments.make()
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "c3", newParentID: "f2"))
        let steps = try document.granularInverse(of: move)
        try document.apply(move)
        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "c2")))
        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "c1")))
        for step in steps {
            try document.apply(step.resolved(in: document))
        }
        #expect(document.childIDs(of: "f1") == ["c3"])
    }

    @Test("a root-level move lands by anchor in the root order")
    func rootLevelMove() throws {
        let document = SessionTestDocuments.make()
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "f2", newParentID: "f1"))
        let steps = try document.granularInverse(of: move)
        try document.apply(move)
        try foreignInsert("x", into: nil, at: 0, in: document)
        for step in steps {
            try document.apply(step.resolved(in: document))
        }
        #expect(document.rootOrder == ["x", "f1", "f2", "comp1", "ref1"])
    }

    // MARK: - Overrides

    @Test("an override inverse splits per key: restoring an old value and unsetting an added key")
    func overrideDescendantPerKey() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()
        let operation = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#0000ff", "fontSize": 18]
        ))
        let steps = try roundTrip(operation, in: document)
        #expect(Set(steps) == [
            GuardedInverse(
                operation: .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "ref1", descendantID: "inner", properties: ["fill": "#ff0000"]
                )),
                keys: [.override(ref: "ref1", descendant: "inner", key: "fill")]
            ),
            GuardedInverse(
                operation: .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "ref1", descendantID: "inner", properties: [:], unset: ["fontSize"]
                )),
                keys: [.override(ref: "ref1", descendant: "inner", key: "fontSize")]
            ),
        ])
        #expect(document.materialize() == before)
    }

    @Test("an override on a descendant with no entry undoes back to no entry")
    func overrideNewEntry() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()
        let operation = EditOperation.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "label", properties: ["opacity": 0.5]
        ))
        let steps = try roundTrip(operation, in: document)
        #expect(steps.count == 1)
        #expect(document.materialize() == before)
    }

    @Test("a root override inverse splits per key, restoring an unset key and unsetting an added one")
    func overrideRootPerKey() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()
        let operation = EditOperation.overrideRoot(EditOperation.OverrideRoot(
            refNodeID: "ref1", properties: ["height": 30], unset: ["width", "never"]
        ))
        let steps = try roundTrip(operation, in: document)
        #expect(Set(steps) == [
            GuardedInverse(
                operation: .overrideRoot(EditOperation.OverrideRoot(refNodeID: "ref1", properties: ["width": 120])),
                keys: [.rootOverride(ref: "ref1", key: "width")]
            ),
            GuardedInverse(
                operation: .overrideRoot(EditOperation.OverrideRoot(refNodeID: "ref1", properties: [:], unset: ["height"])),
                keys: [.rootOverride(ref: "ref1", key: "height")]
            ),
        ])
        #expect(document.materialize() == before)
    }

    // MARK: - Properties

    @Test("a whole-struct update undoes as one setProperties step per changed path")
    func updateCommonPerPath() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()
        var common = PenNodeCommon(name: "Renamed")
        common.opacity = .literal(0.5)
        let steps = try roundTrip(.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common)), in: document)
        #expect(Set(steps) == [
            GuardedInverse(
                operation: .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "Child1"])),
                keys: [.property(node: "c1", path: "common.name")]
            ),
            GuardedInverse(
                operation: .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.opacity": nil])),
                keys: [.property(node: "c1", path: "common.opacity")]
            ),
        ])
        #expect(document.materialize() == before)
    }

    @Test("a change of node type undoes as one whole updateKind")
    func kindCaseChange() throws {
        let document = SessionTestDocuments.make()
        let before = document.materialize()
        let operation = EditOperation.updateKind(EditOperation.UpdateKind(
            nodeID: "c1", kind: .text(PenNode.TextData(content: .literal("hi")))
        ))
        let steps = try roundTrip(operation, in: document)
        #expect(steps.count == 1)
        #expect(steps.first?.keys.contains(.property(node: "c1", path: ChangeKey.wholeKindPath)) == true)
        #expect(document.materialize() == before)
    }

    // MARK: - Structural and document-level

    @Test("every other kind of edit round-trips through its guarded steps")
    func otherEditsRoundTrip() throws {
        let inserted = PenNode(id: "n1", common: PenNodeCommon(name: "New"), kind: .rectangle(PenNode.RectangleData()))
        let replacement = PenNode(id: "f2", common: PenNodeCommon(name: "Rebuilt"), kind: .frame(PenNode.FrameData()))
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        let operations: [EditOperation] = [
            .insertNode(EditOperation.InsertNode(node: inserted, parentID: "f1", index: 1)),
            .deleteNode(EditOperation.DeleteNode(nodeID: "f1")),
            .replaceSubtree(EditOperation.ReplaceSubtree(node: replacement)),
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["kind.width": 7, "common.name": "n"])),
            .addVariable(EditOperation.AddVariable(name: "accent", variable: variable)),
            .updateVariable(EditOperation.UpdateVariable(name: "primary", variable: variable)),
            .removeVariable(EditOperation.RemoveVariable(name: "primary")),
            .addImport(EditOperation.AddImport(alias: "kit", path: "kit.pen")),
            .updateImport(EditOperation.UpdateImport(alias: "lib", path: "lib2.pen")),
            .removeImport(EditOperation.RemoveImport(alias: "lib")),
            .addThemeAxis(EditOperation.AddThemeAxis(name: "density", options: ["a"])),
            .updateThemeAxis(EditOperation.UpdateThemeAxis(name: "mode", options: ["light"])),
            .removeThemeAxis(EditOperation.RemoveThemeAxis(name: "mode")),
            .setDocumentProperties(EditOperation.SetDocumentProperties(properties: ["fileToken": "t1"])),
            .detachRef(EditOperation.DetachRef(refNodeID: "ref1")),
            .deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach)),
        ]
        for operation in operations {
            let document = SessionTestDocuments.make()
            let before = document.materialize()
            let steps = try roundTrip(operation, in: document)
            #expect(!steps.isEmpty, "\(operation)")
            #expect(steps.allSatisfy { !$0.keys.isEmpty }, "\(operation) has an unguarded step")
            #expect(document.materialize() == before, "\(operation)")
        }
    }
}
