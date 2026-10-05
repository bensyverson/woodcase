//
//  ComponentLoopMergeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A three-way merge whose two sides together would make components contain each other
/// keeps the local side and reports the external change it left out.
@MainActor
struct ComponentLoopMergeTests {
    // MARK: - Helpers

    /// `CmpA` and `CmpB` each hold a text and an instance of `CmpC` (`AC`, `BC`); `Page`
    /// holds an instance of `CmpA` (`PA`).
    private static func base() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "CmpA", "type": "frame", "reusable": true, "children": [
            {"id": "TA", "type": "text", "content": "a"},
            {"id": "AC", "type": "ref", "ref": "CmpC"}
          ]},
          {"id": "CmpB", "type": "frame", "reusable": true, "children": [
            {"id": "TB", "type": "text", "content": "b"},
            {"id": "BC", "type": "ref", "ref": "CmpC"}
          ]},
          {"id": "CmpC", "type": "frame", "reusable": true, "children": [
            {"id": "TC", "type": "text", "content": "c"}
          ]},
          {"id": "Page", "type": "frame", "children": [
            {"id": "PA", "type": "ref", "ref": "CmpA"}
          ]}
        ]}
        """#))
    }

    private static func copy(_ document: EditableDocument) -> EditableDocument {
        EditableDocument(from: document.materialize())
    }

    private static func ref(_ id: String, to target: String) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: target)))
    }

    /// Applies a merge's operations to a copy of ours, as a session does.
    private static func applying(_ result: MergeResult, to ours: EditableDocument) throws -> EditableDocument {
        let merged = copy(ours)
        try merged.allowingComponentLoops {
            for operation in result.operations {
                try merged.apply(operation)
            }
        }
        return merged
    }

    /// The conflicts the loop rule reported.
    private static func loopConflicts(_ result: MergeResult) -> [MergeConflict] {
        result.conflicts.filter { $0.kind == .wouldCloseComponentLoop }
    }

    // MARK: - Tests

    @Test("Each side inserts an instance of the other's component: ours stays, theirs is reported")
    func crossedInsertsKeepOurs() throws {
        let base = try Self.base()
        let ours = Self.copy(base)
        try ours.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("AB", to: "CmpB"), parentID: "CmpA")))
        let theirs = Self.copy(base)
        try theirs.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("BA", to: "CmpA"), parentID: "CmpB")))

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        let merged = try Self.applying(result, to: ours)

        #expect(merged.componentLoops.isEmpty)
        #expect(merged.nodes["AB"] != nil)
        #expect(merged.nodes["BA"] == nil)
        #expect(Self.loopConflicts(result).map(\.subject) == [.existence(nodeID: "BA")])
        #expect(Self.loopConflicts(result).first?.theirs != nil)
        #expect(result.keepsLocalChanges)
    }

    @Test("Each side retargets an instance at the other's component: ours stays, theirs is reported")
    func crossedRetargetsKeepOurs() throws {
        let base = try Self.base()
        let ours = Self.copy(base)
        try ours.apply(.setProperties(EditOperation.SetProperties(nodeID: "AC", properties: ["kind.ref": "CmpB"])))
        let theirs = Self.copy(base)
        try theirs.apply(.setProperties(EditOperation.SetProperties(nodeID: "BC", properties: ["kind.ref": "CmpA"])))
        try theirs.apply(.setProperties(EditOperation.SetProperties(nodeID: "TB", properties: ["kind.content": "theirs"])))

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        let merged = try Self.applying(result, to: ours)

        #expect(merged.componentLoops.isEmpty)
        #expect(Self.loopConflicts(result).map(\.subject) == [.property(nodeID: "BC", path: "kind.ref")])
        #expect(Self.loopConflicts(result).first?.theirs == "CmpA")
        if case let .ref(data)? = merged.nodes["AC"]?.kind { #expect(data.ref == "CmpB") }
        if case let .ref(data)? = merged.nodes["BC"]?.kind { #expect(data.ref == "CmpC") }
        if case let .text(data)? = merged.nodes["TB"]?.kind { #expect(data.content == .literal("theirs")) }
    }

    @Test("Theirs moves an instance into a component ours made it render: the move is reported")
    func crossedMoveKeepsOurs() throws {
        let base = try Self.base()
        let ours = Self.copy(base)
        try ours.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("AB", to: "CmpB"), parentID: "CmpA")))
        let theirs = Self.copy(base)
        try theirs.apply(.moveNode(EditOperation.MoveNode(nodeID: "PA", newParentID: "CmpB")))

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        let merged = try Self.applying(result, to: ours)

        #expect(merged.componentLoops.isEmpty)
        #expect(merged.parents["PA"] == "Page")
        #expect(Self.loopConflicts(result).map(\.subject) == [.parent(nodeID: "PA")])
    }

    @Test("A merge that only passes through a loop between its steps reports nothing")
    func transientLoopIsNoConflict() throws {
        let base = try Self.base()
        try base.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("AB", to: "CmpB"), parentID: "CmpA")))
        let ours = Self.copy(base)
        try ours.apply(.setProperties(EditOperation.SetProperties(nodeID: "TA", properties: ["kind.content": "ours"])))
        let theirs = Self.copy(base)
        try theirs.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "AB")))
        try theirs.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("BA", to: "CmpA"), parentID: "CmpB")))

        let result = DocumentMerge.merge(base: base, ours: ours, theirs: theirs)
        let merged = try Self.applying(result, to: ours)

        #expect(Self.loopConflicts(result).isEmpty)
        #expect(merged.componentLoops.isEmpty)
        #expect(merged.nodes["BA"] != nil && merged.nodes["AB"] == nil)
    }

    @Test("A session's file merge whose steps pass through a loop between two of them lands")
    func sessionMergeThroughTransientLoop() throws {
        let base = try Self.base()
        try base.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("AB", to: "CmpB"), parentID: "CmpA")))
        let session = DocumentSession(
            document: base.materialize(),
            author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")),
            merger: .threeWay
        )
        let theirs = Self.copy(base)
        try theirs.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "AB")))
        try theirs.apply(.insertNode(EditOperation.InsertNode(node: Self.ref("BA", to: "CmpA"), parentID: "CmpB")))

        let change = try session.submit(.file(theirs.materialize(), author: nil))

        #expect(change.conflicts.isEmpty)
        #expect(session.document.componentLoops.isEmpty)
        #expect(session.document.nodes["BA"] != nil && session.document.nodes["AB"] == nil)
    }
}

/// The loop rule costs a merge nothing unless its operations can add a component edge.
@MainActor
struct ComponentLoopMergeCostTests {
    private static func base() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "CmpA", "type": "frame", "reusable": true, "children": [
            {"id": "TA", "type": "text", "content": "a"},
            {"id": "AC", "type": "ref", "ref": "CmpC"}
          ]},
          {"id": "CmpC", "type": "frame", "reusable": true, "children": [
            {"id": "TC", "type": "text", "content": "c"}
          ]},
          {"id": "CmpD", "type": "frame", "reusable": true, "children": []},
          {"id": "Page", "type": "frame", "children": [
            {"id": "PA", "type": "ref", "ref": "CmpA"},
            {"id": "Box", "type": "frame", "children": [{"id": "R1", "type": "rectangle", "width": 10, "height": 10}]}
          ]}
        ]}
        """#))
    }

    private static func merged(_ edit: (EditableDocument) throws -> Void) throws -> (MergeResult, EditableDocument) {
        let base = try Self.base()
        let ours = EditableDocument(from: base.materialize())
        let theirs = EditableDocument(from: base.materialize())
        try edit(theirs)
        return (DocumentMerge.merge(base: base, ours: ours, theirs: theirs), ours)
    }

    @Test("A merge of nudges, fills, overrides of plain values, plain inserts and moves adds no component edge")
    func propertyMergeAddsNoEdge() throws {
        let (result, ours) = try Self.merged { theirs in
            try theirs.apply(.setProperties(EditOperation.SetProperties(nodeID: "R1", properties: ["common.x": 12, "kind.fills": ["#FF0000"]])))
            try theirs.apply(.setProperties(EditOperation.SetProperties(nodeID: "TA", properties: ["kind.content": "theirs"])))
            try theirs.apply(.overrideDescendant(EditOperation.OverrideDescendant(refNodeID: "PA", descendantID: "TA", properties: ["content": "hi"])))
            let rect = PenNode(id: "R2", common: PenNodeCommon(name: "R2"), kind: .rectangle(PenNode.RectangleData()))
            try theirs.apply(.insertNode(EditOperation.InsertNode(node: rect, parentID: "CmpA")))
            try theirs.apply(.moveNode(EditOperation.MoveNode(nodeID: "R1", newParentID: "CmpC")))
        }
        #expect(!result.operations.isEmpty)
        #expect(!DocumentMerge.addsComponentEdge(result.operations, to: ours))
    }

    @Test("A merge that places, retargets or moves an instance, or makes a component, adds an edge")
    func edgeMergesAreSeen() throws {
        let ref = PenNode(id: "PC", common: PenNodeCommon(name: "PC"), kind: .ref(PenNode.RefData(ref: "CmpC")))
        let edits: [(EditableDocument) throws -> Void] = [
            { try $0.apply(.insertNode(EditOperation.InsertNode(node: ref, parentID: "Box"))) },
            { try $0.apply(.setProperties(EditOperation.SetProperties(nodeID: "AC", properties: ["kind.ref": "CmpD"]))) },
            { try $0.apply(.setProperties(EditOperation.SetProperties(nodeID: "Box", properties: ["common.reusable": true]))) },
            { try $0.apply(.moveNode(EditOperation.MoveNode(nodeID: "PA", newParentID: "Box"))) },
        ]
        for (index, edit) in edits.enumerated() {
            let (result, ours) = try Self.merged(edit)
            #expect(DocumentMerge.addsComponentEdge(result.operations, to: ours), "edit \(index)")
        }
    }
}
