//
//  StructuralLayoutScopeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An insert, move or delete outside any component names only the spines it touches —
/// the parent it leaves and the parent it enters, with their ancestors — and a layout
/// pass lays out exactly those containers (leaf `df281f`). No board is laid out whole,
/// every other board keeps its rects, and the result still equals a full layout
/// (``LayoutOracle``).
@MainActor
struct StructuralLayoutScopeTests {
    @Test("An insert into one list lays out only the list and its board")
    func insertLaysOutItsSpine() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("b1Row4", "B1 row four"), parentID: "b1List", index: 1
        )))
        #expect(fixture.document.layoutInvalidation.roots.isEmpty)
        #expect(!fixture.document.isLayoutFullyInvalidated)

        let change = try fixture.layOut()
        #expect(change.affectedRoots == ["B1"])
        #expect(Set(change.stats.containersLaidOut) == ["b1List", "B1"])
    }

    @Test("A delete from one list lays out only the list and its board")
    func deleteLaysOutItsSpine() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.deleteNode(EditOperation.DeleteNode(nodeID: "b1Row2")))
        #expect(change.affectedRoots == ["B1"])
        #expect(Set(change.stats.containersLaidOut) == ["b1List", "B1"])
        #expect(change.removed == ["b1Row2"])
    }

    @Test("A move within one list lays out only the list and its board")
    func moveWithinLaysOutItsSpine() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row3", newParentID: "b1List", index: 0
        )))
        #expect(change.affectedRoots == ["B1"])
        #expect(Set(change.stats.containersLaidOut) == ["b1List", "B1"])
        #expect(change.moved.isSuperset(of: ["b1Row1", "b1Row2", "b1Row3"]))
    }

    @Test("A move between boards lays out both spines and nothing else")
    func moveBetweenLaysOutBothSpines() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row2", newParentID: "b4List", index: 0
        )))
        #expect(change.affectedRoots == ["B1", "B4"])
        #expect(Set(change.stats.containersLaidOut) == ["b1List", "B1", "b4List", "B4"])
    }

    @Test("Dirty layout ids name the edited spine, before and after a move")
    func dirtySpineCoversBothParents() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row2", newParentID: "b4List", index: 0
        )))
        #expect(fixture.document.dirtyLayoutNodeIDs == ["b1Row2", "b1List", "B1", "b4List", "B4"])
    }

    @Test("A new top-level board is laid out alone")
    func insertedRootIsLaidOut() throws {
        let fixture = try StructuralLayoutFixture()
        let board = PenNode(
            id: "B7",
            common: PenNodeCommon(x: .literal(3000), y: .literal(0)),
            kind: .frame(PenNode.FrameData(
                layout: .vertical,
                children: [StructuralLayoutFixture.text("b7Title", "B7 title")]
            ))
        )
        let change = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(node: board, parentID: nil)))
        #expect(change.affectedRoots == ["B7"])
        #expect(change.stats.containersLaidOut == ["B7"])
    }

    @Test("Deleting a top-level board lays out nothing and drops its rects")
    func deletedRootLaysOutNothing() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.deleteNode(EditOperation.DeleteNode(nodeID: "B4")))
        #expect(change.affectedRoots.isEmpty)
        #expect(change.stats.containersLaidOut.isEmpty)
        #expect(change.removed.isSuperset(of: ["B4", "b4Title", "b4List", "b4Row1"]))
    }

    @Test("Inserting a component lays out the board whose dangling ref now resolves")
    func insertedComponentResolvesADanglingRef() throws {
        let fixture = try StructuralLayoutFixture()
        var ghost = StructuralLayoutFixture.text("Ghost", "Ghost text")
        ghost.common.reusable = true
        let change = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(node: ghost, parentID: "b1List")))
        #expect(fixture.document.dirtyLayoutNodeIDs.isSuperset(of: ["b4Ghost", "B4"]))
        #expect(change.affectedRoots == ["B1", "B4"])
    }

    @Test("The structural subjects stay visible to a host until the dirty tracking is cleared")
    func structuralSubjectsAreReported() throws {
        let fixture = try StructuralLayoutFixture()
        #expect(fixture.document.structurallyEditedNodeIDs.isEmpty)
        try fixture.document.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row2", newParentID: "b4List", index: 0
        )))
        try fixture.document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "b1Row1", properties: ["kind.content": .string("Not structural")]
        )))
        #expect(fixture.document.structurallyEditedNodeIDs == ["b1Row2", "b4List"])

        fixture.document.clearDirtyNodes()
        #expect(fixture.document.structurallyEditedNodeIDs.isEmpty)
    }
}
