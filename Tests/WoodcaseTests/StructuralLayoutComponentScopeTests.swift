//
//  StructuralLayoutComponentScopeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An insert, move or delete inside a component lays out exactly the placed instances
/// of it — transitively, through components that nest one — and their spines, and
/// nothing else (Penumbra ruling R20, narrowed to instances 2026-10-12).
@MainActor
struct StructuralLayoutComponentScopeTests {
    /// The placed instances that draw `Card`, with their spines: `b2Card` in `B2`,
    /// `b3Panel` (an instance of `Panel`, which nests it) in `B3`, and `R5` (a top-level
    /// instance).
    private static let cardInstanceSpines: Set<String> = ["b2Card", "B2", "b3Panel", "B3", "R5"]

    /// The roots a layout pass lays out, by expanded id: the
    /// components themselves are not laid out on their own, and the top-level instance
    /// `R5` expands to `R5/Card`.
    private static let cardWalked: Set<String> = ["B2", "B3", "R5/Card"]

    @Test("An insert inside a component lays out exactly the boards that draw it")
    func insertInsideComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("cardBodyMore", "Card body more"), parentID: "cardBody"
        )))
        #expect(change.affectedRoots == Self.cardWalked)
        #expect(fixture.document.dirtyLayoutNodeIDs.isSuperset(of: Self.cardInstanceSpines))
        #expect(fixture.document.layoutInvalidation.roots.isEmpty)
    }

    @Test("A delete inside a component lays out exactly the boards that draw it")
    func deleteInsideComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.deleteNode(EditOperation.DeleteNode(nodeID: "cardBodyText")))
        #expect(change.affectedRoots == Self.cardWalked)
        #expect(fixture.document.dirtyLayoutNodeIDs.isSuperset(of: Self.cardInstanceSpines))
        #expect(fixture.document.layoutInvalidation.roots.isEmpty)
    }

    @Test("A move inside a component lays out exactly the boards that draw it")
    func moveInsideComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.moveNode(EditOperation.MoveNode(
            nodeID: "cardTitle", newParentID: "cardBody", index: 0
        )))
        #expect(change.affectedRoots == Self.cardWalked)
        #expect(fixture.document.dirtyLayoutNodeIDs.isSuperset(of: Self.cardInstanceSpines))
        #expect(fixture.document.layoutInvalidation.roots.isEmpty)
    }

    @Test("An edit inside the nesting component skips boards that hold only the inner one")
    func insertInsideOuterComponent() throws {
        let fixture = try StructuralLayoutFixture()
        let change = try fixture.applyAndLayOut(.insertNode(EditOperation.InsertNode(
            node: StructuralLayoutFixture.text("panelFooter", "Panel footer"), parentID: "Panel"
        )))
        #expect(change.affectedRoots == ["B3"])
        #expect(fixture.document.dirtyLayoutNodeIDs.isSuperset(of: ["b3Panel", "B3"]))
        #expect(!fixture.document.dirtyLayoutNodeIDs.contains("b2Card"))
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
        #expect(document.dirtyLayoutNodeIDs.isSuperset(of: ["boardA", "Board"]))
    }
}
