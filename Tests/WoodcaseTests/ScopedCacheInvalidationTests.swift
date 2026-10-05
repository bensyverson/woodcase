//
//  ScopedCacheInvalidationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An edit inside a component forgets what renders that component, and nothing else.
///
/// The document: `C0` is a component, `C1` nests an instance of it (`C1n`), `C2` stands
/// alone, and a page holds one instance of each beside a plain rectangle. Every test warms
/// a cache, edits, and checks both halves of the rule — what must be forgotten is, what
/// cannot have changed is kept — and that the cache still agrees with a document built
/// from scratch.
@MainActor
struct ScopedCacheInvalidationTests {
    /// A node named by its id.
    private static func node(_ id: String, _ kind: PenNode.Kind, reusable: Bool = false) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: id, reusable: reusable ? true : nil), kind: kind)
    }

    /// A 10×10 rectangle.
    private static func rect(_ id: String) -> PenNode {
        node(id, .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10))))
    }

    /// An instance of a component.
    private static func instance(_ id: String, of component: String) -> PenNode {
        node(id, .ref(PenNode.RefData(ref: component)))
    }

    /// A frame holding children.
    private static func frame(_ id: String, _ children: [PenNode], reusable: Bool = false) -> PenNode {
        node(id, .frame(PenNode.FrameData(children: children)), reusable: reusable)
    }

    /// The three components and the page.
    static func document() -> PenDocument {
        PenDocument(children: [
            frame("C0", [rect("C0a")], reusable: true),
            frame("C1", [rect("C1a"), instance("C1n", of: "C0")], reusable: true),
            frame("C2", [rect("C2a")], reusable: true),
            frame("Page", [instance("I0", of: "C0"), instance("I1", of: "C1"), instance("I2", of: "C2"), rect("R")]),
        ])
    }

    /// Every node's revision, filling the cache.
    @discardableResult
    private func revisions(of document: EditableDocument) -> [String: String] {
        document.nodes.keys.reduce(into: [:]) { $0[$1] = document.revision(of: $1) }
    }

    /// Every node's revision as a document with no cache computes it.
    private func scratchRevisions(of document: EditableDocument) -> [String: String] {
        revisions(of: EditableDocument(from: document.materialize()))
    }

    /// Nudges a node.
    private func nudge(_ nodeID: String, in document: EditableDocument) throws {
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.x": .int(7)])))
    }

    // MARK: - Revisions

    @Test("an edit inside a component forgets every revision that renders it, through nesting")
    func componentEditForgetsItsRenderers() throws {
        let document = EditableDocument(from: Self.document())
        revisions(of: document)

        try nudge("C0a", in: document)

        let cached = try #require(document.revisionCache).entries
        for forgotten in ["C0a", "C0", "I0", "C1n", "C1", "I1", "Page"] {
            #expect(cached[forgotten] == nil, "\(forgotten) is still cached")
        }
        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("an edit inside a component keeps every revision that cannot render it")
    func componentEditKeepsTheRest() throws {
        let document = EditableDocument(from: Self.document())
        revisions(of: document)

        try nudge("C0a", in: document)

        let cached = try #require(document.revisionCache).entries
        for kept in ["C1a", "C2", "C2a", "I2", "R"] {
            #expect(cached[kept] != nil, "\(kept) was forgotten")
        }
    }

    @Test("an edit keeps the encoding of every node it did not write")
    func encodingsSurviveForgetting() throws {
        let document = EditableDocument(from: Self.document())
        revisions(of: document)

        try nudge("C0a", in: document)

        let encodings = try #require(document.revisionCache).encodings
        #expect(encodings["C0a"] == nil)
        for kept in ["C0", "I0", "C1n", "C1", "I1", "Page"] {
            #expect(encodings[kept] != nil, "\(kept)'s encoding was forgotten")
        }
        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("a detach's nested instances render what they rendered before it")
    func detachIndexesItsInstances() throws {
        let document = EditableDocument(from: Self.document())
        revisions(of: document)
        try nudge("R", in: document)

        try document.apply(.detachRef(EditOperation.DetachRef(refNodeID: "I1")))
        revisions(of: document)
        try nudge("C0a", in: document)

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    // MARK: - Expansions and loops

    @Test("an edit inside a component drops the expansions of its instances and keeps the others")
    func componentEditScopesExpansions() throws {
        let document = EditableDocument(from: Self.document())
        for ref in ["I0", "I1", "I2"] {
            _ = try document.expandRef(nodeID: ref)
        }

        try nudge("C0a", in: document)

        let cached = try #require(document.expansionCache).entries
        #expect(cached["I0"] == nil)
        #expect(cached["I1"] == nil)
        #expect(cached["I2"] != nil)
        let scratch = EditableDocument(from: document.materialize())
        for ref in ["I0", "I1", "I2"] {
            #expect(try document.expandRef(nodeID: ref) == scratch.expandRef(nodeID: ref))
        }
    }

    @Test("an edit that renders nothing new inside a component keeps the memoized loops")
    func nudgeKeepsLoops() throws {
        let document = EditableDocument(from: Self.document())
        _ = document.componentLoopIndex

        try nudge("C0a", in: document)
        try document.apply(.insertNode(EditOperation.InsertNode(node: Self.rect("C0b"), parentID: "C0")))

        #expect(document.expansionCache?.componentLoops != nil)
    }

    @Test("an edit that places an instance inside a component drops the memoized loops")
    func instanceInsertDropsLoops() throws {
        let document = EditableDocument(from: Self.document())
        _ = document.componentLoopIndex

        try document.apply(.insertNode(EditOperation.InsertNode(node: Self.instance("C2n", of: "C2"), parentID: "C0")))

        #expect(document.expansionCache?.componentLoops == nil)
        #expect(document.componentLoopIndex == EditableDocument(from: document.materialize()).componentLoopIndex)
    }

    @Test("moving a frame that holds an instance into a component drops the memoized loops")
    func carryingMoveDropsLoops() throws {
        let document = EditableDocument(from: Self.document())
        try document.apply(.insertNode(EditOperation.InsertNode(
            node: Self.frame("Box", [Self.instance("BoxI", of: "C2")]), parentID: "Page"
        )))
        _ = document.componentLoopIndex

        try document.apply(.moveNode(EditOperation.MoveNode(nodeID: "Box", newParentID: "C0")))

        #expect(document.componentLoopIndex == EditableDocument(from: document.materialize()).componentLoopIndex)
    }
}
