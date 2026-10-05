//
//  StructuralLayoutScopeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An insert, move or delete lays out only the top-level boards it can change
/// (Penumbra ruling R20): the board that holds it, and the boards a move leaves or
/// enters. Every other board keeps its rects, and the result still equals a full
/// layout (``LayoutOracle``).
@MainActor
struct StructuralLayoutScopeTests {
    @Test("An insert into one board lays out only that board")
    func insertLaysOutItsBoard() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("b1Row4", "B1 row four"), parentID: "b1List", index: 1
        )))
        #expect(walked == ["B1"])
        #expect(fixture.document.dirtyLayoutRootIDs == ["B1"])
        #expect(!fixture.document.isLayoutFullyInvalidated)
    }

    @Test("A delete from one board lays out only that board")
    func deleteLaysOutItsBoard() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.deleteNode(EditOperation.DeleteNode(nodeID: "b1Row2")))
        #expect(walked == ["B1"])
        #expect(fixture.document.dirtyLayoutRootIDs == ["B1"])
    }

    @Test("A move within one board lays out only that board")
    func moveWithinLaysOutItsBoard() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row3", newParentID: "b1List", index: 0
        )))
        #expect(walked == ["B1"])
    }

    @Test("A move between boards lays out both and nothing else")
    func moveBetweenLaysOutBoth() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row2", newParentID: "b4List", index: 0
        )))
        #expect(walked == ["B1", "B4"])
        #expect(fixture.document.dirtyLayoutRootIDs == ["B1", "B4"])
    }

    @Test("Dirty layout ids name the edited spine, before and after a move")
    func dirtySpineCoversBothParents() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "b1Row2", newParentID: "b4List", index: 0
        )))
        #expect(fixture.document.dirtyLayoutNodeIDs.isSuperset(of: ["b1Row2", "b1List", "B1", "b4List", "B4"]))
        #expect(!fixture.document.dirtyLayoutNodeIDs.contains("B2"))
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
        let walked = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(node: board, parentID: nil)))
        #expect(walked.isEmpty)
        #expect(fixture.recorder.texts.contains("B7 title"))
    }

    @Test("Deleting a top-level board lays out nothing and drops its rects")
    func deletedRootLaysOutNothing() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.deleteNode(EditOperation.DeleteNode(nodeID: "B4")))
        #expect(walked.isEmpty)
        #expect(fixture.recorder.texts.isEmpty)
    }

    @Test("Inserting a component lays out the board whose dangling ref now resolves")
    func insertedComponentResolvesADanglingRef() throws {
        let fixture = try StructuralLayoutFixture()
        var ghost = StructuralLayoutFixture.text("Ghost", "Ghost text")
        ghost.common.reusable = true
        let walked = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(node: ghost, parentID: "b1List")))
        #expect(walked == ["B1", "B4"])
    }
}
