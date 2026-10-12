//
//  PenLayoutIndexTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The expanded-id index: where each node of an expanded document sits, and the
/// translation of a source dirty set into the expanded ids layout must redo.
@MainActor
struct PenLayoutIndexTests {
    /// ``StructuralLayoutFixture``'s document expanded for export, indexed.
    private func makeIndex() throws -> PenLayoutIndex {
        let fixture = try StructuralLayoutFixture()
        return PenLayoutIndex(fixture.document.expandedDocument().0)
    }

    // MARK: - Indexing

    @Test("Each node records its parent, its index among siblings, its depth and its root")
    func entries() throws {
        let index = try makeIndex()
        #expect(index["b1Row2"] == PenLayoutIndex.Entry(parent: "b1List", index: 1, depth: 2, root: "B1"))
        #expect(index["b2Card/cardBodyText"] == PenLayoutIndex.Entry(
            parent: "b2Card/cardBody", index: 0, depth: 3, root: "B2"
        ))
        #expect(index["R5/Card"] == PenLayoutIndex.Entry(parent: nil, index: 4, depth: 0, root: "R5/Card"))
        #expect(index["Card"] == nil, "an export expansion strips the definition")
    }

    @Test("Roots, children, ancestors and subtrees read back in document order")
    func treeReads() throws {
        let index = try makeIndex()
        #expect(index.roots == ["B1", "B2", "B3", "B4", "R5/Card"])
        #expect(index.children(of: "b1List") == ["b1Row1", "b1Row2", "b1Row3"])
        #expect(index.children(of: "b1Row1").isEmpty)
        #expect(index.ancestors(of: "b2Card/cardBodyText") == ["b2Card/cardBody", "b2Card/Card", "B2"])
        #expect(index.subtree(of: "b2Card/Card") == [
            "b2Card/Card", "b2Card/cardTitle", "b2Card/cardBody", "b2Card/cardBodyText",
        ])
        #expect(index.subtree(of: "missing").isEmpty)
    }

    @Test("A ref's instance roots are the outermost nodes expanded under its id")
    func instanceRoots() throws {
        let index = try makeIndex()
        #expect(index.instanceRoots(of: "b2Card") == ["b2Card/Card"])
        #expect(index.instanceRoots(of: "b3Panel") == ["b3Panel/Panel"], "a nested instance is not a root of the outer one")
        #expect(index.instanceRoots(of: "R5") == ["R5/Card"])
        #expect(index.instanceRoots(of: "b1List").isEmpty)
    }

    // MARK: - Translation

    @Test("A plain node keeps its id and brings its ancestors")
    func plainNode() throws {
        let index = try makeIndex()
        let ids = index.expandedIDs(for: PenLayoutInvalidation(nodes: ["b1Row2"]))
        #expect(ids == ["b1Row2", "b1List", "B1"])
    }

    @Test("A ref names its instance, whole")
    func refNamesItsInstance() throws {
        let index = try makeIndex()
        let ids = index.expandedIDs(for: PenLayoutInvalidation(nodes: ["b2Card"]))
        #expect(ids == ["B2", "b2Card/Card", "b2Card/cardTitle", "b2Card/cardBody", "b2Card/cardBodyText"])
    }

    @Test("A subtree names every node under it and its ancestors")
    func subtree() throws {
        let index = try makeIndex()
        let ids = index.expandedIDs(for: PenLayoutInvalidation(subtrees: ["b1List"]))
        #expect(ids == ["B1", "b1List", "b1Row1", "b1Row2", "b1Row3"])
    }

    @Test("A root names its expanded root whole, a top-level instance included")
    func roots() throws {
        let index = try makeIndex()
        let ids = index.expandedIDs(for: PenLayoutInvalidation(roots: ["R5", "B4", "Card"]))
        #expect(ids == [
            "R5/Card", "R5/cardTitle", "R5/cardBody", "R5/cardBodyText",
            "B4", "b4Title", "b4List", "b4Row1", "b4Ghost",
        ])
    }

    @Test("Ids the expanded document does not hold name nothing")
    func absent() throws {
        let index = try makeIndex()
        let ids = index.expandedIDs(for: PenLayoutInvalidation(
            nodes: ["cardBodyText", "cardBody", "Card"], subtrees: ["gone"], roots: ["Panel"]
        ))
        #expect(ids.isEmpty)
    }

    @Test("Everything names every node")
    func everything() throws {
        let index = try makeIndex()
        let ids = index.expandedIDs(for: PenLayoutInvalidation(everything: true))
        #expect(ids.count == index.count)
        #expect(ids.contains("b3Panel/panelCard/cardBodyText"))
    }
}
