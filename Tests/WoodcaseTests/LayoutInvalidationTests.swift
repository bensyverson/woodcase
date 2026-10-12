//
//  LayoutInvalidationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What an edit records for layout, by source id: ``EditableDocument/layoutInvalidation``.
///
/// An edit clear of every component names its node and spine. An edit that expansion can
/// carry elsewhere — inside a component — falls back to the roots whose revision it moved:
/// those are exactly the boards that draw what changed.
@MainActor
struct LayoutInvalidationTests {
    /// Every present root's revision.
    private func rootRevisions(of document: EditableDocument) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: document.rootOrder.map { ($0, document.revision(of: $0)) })
    }

    @Test("An edit clear of every component names its spine and no root")
    func plainEdit() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "b1Row1", properties: ["kind.content": .string("Longer row")]
        )))
        let invalidation = fixture.document.layoutInvalidation
        #expect(invalidation.nodes == ["b1Row1", "b1List", "B1"])
        #expect(invalidation.roots.isEmpty)
        #expect(invalidation.subtrees.isEmpty)
        #expect(!invalidation.everything)
    }

    @Test("An edit inside a component names the placed instances in the roots whose revision moved")
    func definitionEditNamesPlacedInstances() throws {
        let fixture = try StructuralLayoutFixture()
        let before = rootRevisions(of: fixture.document)
        try fixture.document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "cardBodyText", properties: ["kind.content": .string("Edited body")]
        )))
        let after = rootRevisions(of: fixture.document)
        let moved = Set(before.keys.filter { before[$0] != after[$0] })

        #expect(moved == ["Card", "Panel", "B2", "B3", "R5"])
        let invalidation = fixture.document.layoutInvalidation
        #expect(invalidation.roots.isEmpty)
        // Each instance with its spine, up to exactly the roots whose revision moved —
        // `panelCard` inside `Panel` too, which a canvas lays out like a board.
        #expect(invalidation.nodes.isSuperset(of: ["b2Card", "B2", "b3Panel", "B3", "R5", "panelCard", "Panel"]))
        #expect(invalidation.nodes.isSuperset(of: ["cardBodyText", "cardBody", "Card"]))
        let namedRoots = invalidation.nodes.filter { fixture.document.parents[$0] == nil }
        #expect(namedRoots == moved, "the named spines reach exactly the moved roots")
    }

    @Test("Toggling reusable names the placed instances drawing the node")
    func reusableToggle() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Card", properties: ["common.reusable": .bool(false)]
        )))
        #expect(fixture.document.layoutInvalidation.nodes.isSuperset(of: ["b2Card", "b3Panel", "R5", "Card"]))
    }

    @Test("A theme change names the node's whole subtree")
    func themeChange() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "b1List", properties: ["common.theme": .dictionary(["mode": .string("dark")])]
        )))
        let invalidation = fixture.document.layoutInvalidation
        #expect(invalidation.subtrees == ["b1List"])
        #expect(invalidation.nodes.isSuperset(of: ["b1List", "B1"]))
    }

    @Test("An override names its ref, which the index reads as the whole instance")
    func override() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "b2Card", descendantID: "cardTitle", properties: ["content": .string("New title")]
        )))
        let invalidation = fixture.document.layoutInvalidation
        #expect(invalidation.nodes == ["b2Card", "B2"])
        let index = PenLayoutIndex(fixture.document.expandedDocument().0)
        #expect(index.expandedIDs(for: invalidation).isSuperset(of: ["b2Card/Card", "b2Card/cardTitle"]))
    }

    @Test("A variable change invalidates everything; clearing forgets it all")
    func everythingAndClear() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.document.apply(.addVariable(EditOperation.AddVariable(
            name: "gap", variable: PenVariable(type: .number, value: .simple(.int(4)))
        )))
        #expect(fixture.document.layoutInvalidation.everything)
        fixture.document.clearDirtyNodes()
        #expect(fixture.document.layoutInvalidation == PenLayoutInvalidation())
    }
}
