//
//  ComponentLoopQueryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An editor asks, before any edit, whether a drop, paste or swap would close a component
/// loop, and gets the same answer the guard would give the edit (leaf VWmf6D, 5L1).
@MainActor
struct ComponentLoopQueryTests {
    /// `CmpA` ("Card") holds an instance of `CmpB` ("Badge"); `CmpB` holds a box and an
    /// instance of `CmpC`; `Hold` is a plain frame holding an instance of `CmpA`; `Page`
    /// is a plain frame.
    private static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "CmpA", "name": "Card", "type": "frame", "reusable": true, "children": [
            {"id": "AB", "type": "ref", "ref": "CmpB"}
          ]},
          {"id": "CmpB", "name": "Badge", "type": "frame", "reusable": true, "children": [
            {"id": "BBox", "type": "frame", "children": []},
            {"id": "BC", "type": "ref", "ref": "CmpC"}
          ]},
          {"id": "CmpC", "type": "frame", "reusable": true, "children": []},
          {"id": "Hold", "type": "frame", "children": [
            {"id": "HoldA", "type": "ref", "ref": "CmpA"}
          ]},
          {"id": "Page", "type": "frame", "children": []}
        ]}
        """#))
    }

    private static let cardBadge = ComponentLoop(members: [
        ComponentLoop.Member(id: "CmpB", name: "Badge"),
        ComponentLoop.Member(id: "CmpA", name: "Card"),
    ])

    /// The query and the guard agree: the edit the query describes is refused with the
    /// same loop, or goes through when the query found none.
    private static func expectGuardAgrees(
        _ operation: EditOperation, loop: ComponentLoop?, in document: EditableDocument,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try document.validate(operation)
            #expect(loop == nil, "the guard took an edit the query called a loop", sourceLocation: sourceLocation)
        } catch let EditingError.wouldCloseComponentLoop(path) {
            #expect(loop?.ids == Array(path.dropLast()), sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test("Placing an instance of a component inside one it renders names the loop")
    func placingClosesLoop() throws {
        let document = try Self.document()
        let revision = document.documentRevision

        let loop = document.componentLoop(placingInstanceOf: "CmpA", under: "BBox")

        #expect(loop == Self.cardBadge)
        #expect(loop?.description == "Badge → Card → Badge")
        #expect(document.documentRevision == revision)
        Self.expectGuardAgrees(
            .insertNode(.init(node: PenNode(id: "BA", common: PenNodeCommon(), kind: .ref(.init(ref: "CmpA"))), parentID: "BBox")),
            loop: loop, in: document
        )
    }

    @Test("Placing an instance of a component inside itself is a loop of one")
    func placingInsideItself() throws {
        let document = try Self.document()
        #expect(document.componentLoop(placingInstanceOf: "CmpA", under: "CmpA")?.ids == ["CmpA"])
    }

    @Test("Placing an instance where no component renders it back is no loop")
    func placingWithoutLoop() throws {
        let document = try Self.document()
        #expect(document.componentLoop(placingInstanceOf: "CmpA", under: "Page") == nil)
        #expect(document.componentLoop(placingInstanceOf: "CmpA", under: nil) == nil)
        #expect(document.componentLoop(placingInstanceOf: "CmpC", under: "BBox") == nil)
        #expect(document.componentLoop(placingInstanceOf: "Missing", under: "BBox") == nil)
    }

    @Test("Swapping an instance's component to one that renders its own component names the loop")
    func swapClosesLoop() throws {
        let document = try Self.document()

        let loop = document.componentLoop(swapping: "BC", to: "CmpA")

        #expect(loop == Self.cardBadge)
        #expect(document.componentLoop(swapping: "AB", to: "CmpC") == nil)
        #expect(document.componentLoop(swapping: "HoldA", to: "CmpB") == nil)
        #expect(document.componentLoop(swapping: "Page", to: "CmpA") == nil)
        Self.expectGuardAgrees(
            .updateKind(.init(nodeID: "BC", kind: .ref(.init(ref: "CmpA")))), loop: loop, in: document
        )
    }

    @Test("Moving a subtree that holds an instance under a component it would loop names the loop")
    func moveClosesLoop() throws {
        let document = try Self.document()
        let revision = document.documentRevision

        let loop = document.componentLoop(moving: "Hold", under: "BBox")

        #expect(loop == Self.cardBadge)
        #expect(document.componentLoop(moving: "Hold", under: "Page") == nil)
        #expect(document.componentLoop(moving: "BBox", under: "Page") == nil)
        #expect(document.documentRevision == revision)
        Self.expectGuardAgrees(.moveNode(.init(nodeID: "Hold", newParentID: "BBox")), loop: loop, in: document)
    }

    @Test("Inserting a pasted subtree that holds an instance names the loop")
    func insertSubtreeClosesLoop() throws {
        let document = try Self.document()
        let pasted = PenNode(
            id: "Pasted", common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "PastedA", common: PenNodeCommon(), kind: .ref(.init(ref: "CmpA"))),
            ]))
        )

        #expect(document.componentLoop(inserting: pasted, under: "BBox") == Self.cardBadge)
        #expect(document.componentLoop(inserting: pasted, under: "Page") == nil)
    }

    @Test("A loop the document already holds is not reported again")
    func existingLoopIsNotNew() throws {
        let document = try EditableDocument(from: PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "CmpA", "type": "frame", "reusable": true, "children": [
            {"id": "AB", "type": "ref", "ref": "CmpB"}
          ]},
          {"id": "CmpB", "type": "frame", "reusable": true, "children": [
            {"id": "BA", "type": "ref", "ref": "CmpA"}
          ]}
        ]}
        """#))
        #expect(!document.componentLoops.isEmpty)
        #expect(document.componentLoop(placingInstanceOf: "CmpA", under: "CmpB") == nil)
    }
}
