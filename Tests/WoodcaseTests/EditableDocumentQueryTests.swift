//
//  EditableDocumentQueryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentQueryTests {
    // MARK: - Helpers

    /// Creates an editable document with: frame(f1) > [rect(c1), text(c2)], rect(r1)
    private func makeTestDocument() -> EditableDocument {
        let c1 = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let c2 = PenNode(id: "c2", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [c1, c2]))
        )
        let r1 = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [frame, r1])
        return EditableDocument(from: doc)
    }

    /// Creates a deeply nested doc: frame(f1) > frame(f2) > text(t1)
    private func makeDeepDocument() -> EditableDocument {
        let text = PenNode(id: "t1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let inner = PenNode(
            id: "f2",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [text]))
        )
        let outer = PenNode(
            id: "f1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [inner]))
        )
        return EditableDocument(from: PenDocument(children: [outer]))
    }

    // MARK: - node(id:)

    @Test("node(id:) returns node when it exists")
    func nodeFound() {
        let editable = makeTestDocument()
        let node = editable.node(id: "c1")
        #expect(node != nil)
        #expect(node?.id == "c1")
    }

    @Test("node(id:) returns nil for unknown ID")
    func nodeNotFound() {
        let editable = makeTestDocument()
        #expect(editable.node(id: "nonexistent") == nil)
    }

    // MARK: - parentID(of:)

    @Test("parentID returns parent for child node")
    func parentOfChild() {
        let editable = makeTestDocument()
        #expect(editable.parentID(of: "c1") == "f1")
    }

    @Test("parentID returns nil for root node")
    func parentOfRoot() {
        let editable = makeTestDocument()
        #expect(editable.parentID(of: "f1") == nil)
    }

    // MARK: - childIDs(of:)

    @Test("childIDs returns ordered children for container")
    func childIDsOfContainer() {
        let editable = makeTestDocument()
        #expect(editable.childIDs(of: "f1") == ["c1", "c2"])
    }

    @Test("childIDs returns empty array for leaf")
    func childIDsOfLeaf() {
        let editable = makeTestDocument()
        #expect(editable.childIDs(of: "c1") == [])
    }

    @Test("childIDs returns empty array for unknown ID")
    func childIDsOfUnknown() {
        let editable = makeTestDocument()
        #expect(editable.childIDs(of: "nope") == [])
    }

    // MARK: - ancestors(of:)

    @Test("ancestors returns path from node to root, excluding self")
    func ancestorsDeep() {
        let editable = makeDeepDocument()
        #expect(editable.ancestors(of: "t1") == ["f2", "f1"])
    }

    @Test("ancestors returns empty for root node")
    func ancestorsRoot() {
        let editable = makeDeepDocument()
        #expect(editable.ancestors(of: "f1") == [])
    }

    @Test("ancestors returns single parent for direct child")
    func ancestorsDirect() {
        let editable = makeTestDocument()
        #expect(editable.ancestors(of: "c1") == ["f1"])
    }

    // MARK: - isDescendant

    @Test("isDescendant returns true for direct child")
    func isDescendantDirect() {
        let editable = makeTestDocument()
        #expect(editable.isDescendant("c1", of: "f1"))
    }

    @Test("isDescendant returns true for transitive descendant")
    func isDescendantTransitive() {
        let editable = makeDeepDocument()
        #expect(editable.isDescendant("t1", of: "f1"))
    }

    @Test("isDescendant returns false for unrelated nodes")
    func isDescendantUnrelated() {
        let editable = makeTestDocument()
        #expect(!editable.isDescendant("r1", of: "f1"))
    }

    @Test("isDescendant returns false for self")
    func isDescendantSelf() {
        let editable = makeTestDocument()
        #expect(!editable.isDescendant("f1", of: "f1"))
    }

    // MARK: - allNodeIDs

    @Test("allNodeIDs returns all IDs")
    func allNodeIDs() {
        let editable = makeTestDocument()
        let ids = editable.allNodeIDs
        #expect(ids.count == 4)
        #expect(ids.contains("f1"))
        #expect(ids.contains("c1"))
        #expect(ids.contains("c2"))
        #expect(ids.contains("r1"))
    }

    // MARK: - rootNodes

    @Test("rootNodes returns materialized root nodes in order")
    func rootNodes() {
        let editable = makeTestDocument()
        let roots = editable.rootNodes
        #expect(roots.count == 2)
        #expect(roots[0].id == "f1")
        #expect(roots[1].id == "r1")
        // The frame root should have its children reconstructed
        if case let .frame(data) = roots[0].kind {
            #expect(data.children?.count == 2)
        } else {
            Issue.record("Expected frame kind")
        }
    }
}
