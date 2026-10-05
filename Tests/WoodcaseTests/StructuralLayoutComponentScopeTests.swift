//
//  StructuralLayoutComponentScopeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An insert, move or delete inside a component lays out the component's own board
/// and exactly the boards that hold an instance of it — transitively, through
/// components that nest one — and nothing else (Penumbra ruling R20).
@MainActor
struct StructuralLayoutComponentScopeTests {
    /// The roots that draw `Card`: itself, `Panel` (nests it), `B2` (an instance),
    /// `B3` (an instance of `Panel`) and `R5` (a top-level instance).
    private static let cardDependents: Set<String> = ["Card", "Panel", "B2", "B3", "R5"]

    /// The roots among ``cardDependents`` a layout pass walks: the components themselves
    /// are not laid out on their own.
    private static let cardWalked: Set<String> = ["B2", "B3", "R5"]

    @Test("An insert inside a component lays out exactly the boards that draw it")
    func insertInsideComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("cardBodyMore", "Card body more"), parentID: "cardBody"
        )))
        #expect(walked == Self.cardWalked)
        #expect(fixture.document.dirtyLayoutRootIDs == Self.cardDependents)
    }

    @Test("A delete inside a component lays out exactly the boards that draw it")
    func deleteInsideComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.deleteNode(EditOperation.DeleteNode(nodeID: "cardBodyText")))
        #expect(walked == Self.cardWalked)
        #expect(fixture.document.dirtyLayoutRootIDs == Self.cardDependents)
    }

    @Test("A move inside a component lays out exactly the boards that draw it")
    func moveInsideComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.moveNode(EditOperation.MoveNode(
            nodeID: "cardTitle", newParentID: "cardBody", index: 0
        )))
        #expect(walked == Self.cardWalked)
        #expect(fixture.document.dirtyLayoutRootIDs == Self.cardDependents)
    }

    @Test("An edit inside the nesting component skips boards that hold only the inner one")
    func insertInsideOuterComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let walked = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("panelFooter", "Panel footer"), parentID: "Panel"
        )))
        #expect(walked == ["B3"])
        #expect(fixture.document.dirtyLayoutRootIDs == ["Panel", "B3"])
    }

    @Test("Components that render each other end the dependency walk")
    func componentLoopTerminates() throws {
        let document = try EditableDocument(from: PenParser.parse("""
        {
          "version": "2.17",
          "children": [
            { "id": "LA", "type": "frame", "reusable": true,
              "children": [ { "id": "laB", "type": "ref", "ref": "LB" } ] },
            { "id": "LB", "type": "frame", "reusable": true,
              "children": [ { "id": "lbA", "type": "ref", "ref": "LA" } ] },
            { "id": "Board", "type": "frame", "children": [ { "id": "boardA", "type": "ref", "ref": "LA" } ] },
            { "id": "Other", "type": "frame", "children": [] }
          ]
        }
        """))
        document.primeLayoutCache(with: ["LA": PenRect(x: 0, y: 0, width: 1, height: 1)])
        try document.apply(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("laText", "Loop"), parentID: "LA"
        )))
        #expect(document.dirtyLayoutRootIDs == ["LA", "LB", "Board"])
    }
}
