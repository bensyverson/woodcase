//
//  EditableDocumentExpansionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentExpansionTests {
    // MARK: - Helpers

    /// Creates a document with a reusable component and a ref to it.
    private func makeComponentDoc() -> PenDocument {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "My Button", x: .literal(100)),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        return PenDocument(children: [component, refNode])
    }

    // MARK: - expandRef

    @Test("expandRef expands a simple ref node")
    func expandRefSimple() throws {
        let doc = makeComponentDoc()
        let editable = EditableDocument(from: doc)

        let result = try editable.expandRef(nodeID: "ref1")

        // Should be a frame, not a ref
        if case .frame = result.expandedNode.kind {
            #expect(result.expandedNode.id == "ref1/comp1")
        } else {
            Issue.record("Expected expanded node to be a frame, got \(result.expandedNode.kind)")
        }

        #expect(result.provenance.componentID == "comp1")
        #expect(result.provenance.instanceRefID == "ref1")
        #expect(result.provenance.appliedOverrides.isEmpty)
    }

    @Test("expandRef with overrides records them in provenance")
    func expandRefWithOverrides() throws {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let overrides: [String: PenDescendantOverride] = [
            "label": PenDescendantOverride(properties: ["name": .string("OK")]),
        ]
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "comp1", descendants: overrides))
        )
        let doc = PenDocument(children: [component, refNode])
        let editable = EditableDocument(from: doc)

        let result = try editable.expandRef(nodeID: "ref1")

        #expect(result.provenance.appliedOverrides["label"] != nil)
    }

    @Test("expandRef throws for non-existent node")
    func expandRefMissing() {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.expandRef(nodeID: "missing")
        }
    }

    @Test("expandRef throws for non-ref node")
    func expandRefNotRef() {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData())
        )
        let doc = PenDocument(children: [rect])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.notARefNode(id: "r1")) {
            try editable.expandRef(nodeID: "r1")
        }
    }

    // MARK: - Caching

    @Test("expandRef uses cache on second call")
    func expandRefCacheHit() throws {
        let doc = makeComponentDoc()
        let editable = EditableDocument(from: doc)

        let first = try editable.expandRef(nodeID: "ref1")
        let second = try editable.expandRef(nodeID: "ref1")

        // Same result
        #expect(first.expandedNode.id == second.expandedNode.id)
        #expect(first.provenance == second.provenance)

        // Cache should contain the entry
        #expect(editable.expansionCache?.entries["ref1"] != nil)
    }

    @Test("Modifying ref overrides invalidates cache")
    func cacheInvalidatedByRefUpdate() throws {
        let doc = makeComponentDoc()
        let editable = EditableDocument(from: doc)

        // Warm the cache
        _ = try editable.expandRef(nodeID: "ref1")
        #expect(editable.expansionCache?.entries["ref1"] != nil)

        // Update the ref's kind (changes overrides)
        try editable.apply(.updateKind(EditOperation.UpdateKind(
            nodeID: "ref1",
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: ["label": PenDescendantOverride(properties: ["name": .string("Cancel")])]
            ))
        )))

        #expect(editable.expansionCache?.entries["ref1"] == nil)
    }

    @Test("Modifying component definition invalidates all referencing caches")
    func cacheInvalidatedByComponentChange() throws {
        let doc = makeComponentDoc()
        let editable = EditableDocument(from: doc)

        _ = try editable.expandRef(nodeID: "ref1")
        #expect(editable.expansionCache?.entries["ref1"] != nil)

        // Update the component's common props (changing its name)
        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "comp1",
            common: PenNodeCommon(name: "Updated Button", reusable: true)
        )))

        #expect(editable.expansionCache?.entries["ref1"] == nil)
    }

    // MARK: - expandedDocument

    @Test("expandedDocument matches PenRefExpander.expand output")
    func expandedDocMatchesRefExpander() {
        let doc = makeComponentDoc()
        let editable = EditableDocument(from: doc)

        let (expandedDoc, context) = editable.expandedDocument()
        let reference = PenRefExpander.expand(doc)

        // Both should have the same children (minus reusables)
        #expect(expandedDoc.children.count == reference.children.count)
        #expect(!context.provenance.isEmpty)
    }

    // MARK: - expandSubtree

    @Test("expandSubtree expands refs within a subtree")
    func expandSubtreeWithRefs() throws {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let container = PenNode(
            id: "container",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [refNode]))
        )
        let doc = PenDocument(children: [component, container])
        let editable = EditableDocument(from: doc)

        let (expanded, context) = try editable.expandSubtree(rootID: "container")

        // The container should now have an expanded child (not a ref)
        if case let .frame(data) = expanded.kind {
            let child = data.children?.first
            #expect(child != nil)
            if case .frame = child?.kind {
                // Good — ref was expanded to frame
            } else {
                Issue.record("Expected expanded child to be frame, got \(String(describing: child?.kind))")
            }
        } else {
            Issue.record("Expected container to be a frame")
        }

        #expect(context.provenance["ref1"] != nil)
    }
}
