//
//  EditOperationDetachTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditOperationDetachTests {
    // MARK: - Helpers

    private func makeRefDoc() -> EditableDocument {
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
            common: PenNodeCommon(x: .literal(100)),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        return EditableDocument(from: PenDocument(children: [component, refNode]))
    }

    // MARK: - Basic Detach

    @Test("Detach removes ref and inserts expanded nodes")
    func detachBasic() throws {
        let editable = makeRefDoc()

        #expect(editable.nodes["ref1"] != nil)

        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        // ref1 should be gone
        #expect(editable.nodes["ref1"] == nil)

        // Should now have expanded nodes with fresh IDs (no slashes)
        let newRootIDs = editable.rootOrder.filter { $0 != "comp1" }
        #expect(newRootIDs.count == 1)

        let newRootID = newRootIDs[0]
        #expect(!newRootID.contains("/"))

        // The new root should be a frame (expanded from the component)
        if case .frame = editable.nodes[newRootID]?.kind {
            // Good
        } else {
            Issue.record("Expected frame kind for detached node")
        }

        // Children should also have fresh IDs
        let childIDs = editable.children[newRootID] ?? []
        for childID in childIDs {
            #expect(!childID.contains("/"))
            #expect(childID.count == 5) // Compact 5-char ID
        }
    }

    @Test("Detach preserves position in parent")
    func detachPreservesPosition() throws {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let before = PenNode(id: "before", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let after = PenNode(id: "after", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let container = PenNode(
            id: "container",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [before, refNode, after]))
        )
        let doc = PenDocument(children: [component, container])
        let editable = EditableDocument(from: doc)

        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        // The detached node should be between "before" and "after"
        let containerChildren = editable.children["container"] ?? []
        #expect(containerChildren.count == 3)
        #expect(containerChildren[0] == "before")
        #expect(containerChildren[2] == "after")
        // Middle element should be the new detached node
        #expect(!containerChildren[1].contains("/"))
    }

    @Test("Detach bakes in overrides")
    func detachBakesOverrides() throws {
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

        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        // Find the detached root
        let detachedRootID = try #require(editable.rootOrder.first { $0 != "comp1" })
        let detachedChildren = editable.children[detachedRootID] ?? []

        // The label's override ("OK") should be baked in
        if let labelID = detachedChildren.first,
           let labelNode = editable.nodes[labelID]
        {
            #expect(labelNode.common.name == "OK")
        } else {
            Issue.record("Expected label child in detached node")
        }
    }

    @Test("Detach returns ID mapping")
    func detachReturnsMapping() throws {
        let editable = makeRefDoc()

        let detachResult = try editable.detachRef(EditOperation.DetachRef(refNodeID: "ref1"))

        #expect(!detachResult.idMapping.isEmpty)
        #expect(!detachResult.rootNodeID.contains("/"))
        #expect(detachResult.rootNodeID.count == 5)

        // All new IDs should be in the document
        for (_, newID) in detachResult.idMapping {
            #expect(editable.nodes[newID] != nil)
        }
    }

    @Test("Detach generates 5-char alphanumeric IDs")
    func detachFreshIDs() throws {
        let editable = makeRefDoc()

        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        for nodeID in editable.nodes.keys where nodeID != "comp1" && nodeID != "label" {
            #expect(!nodeID.contains("/"), "ID '\(nodeID)' contains '/'")
            #expect(nodeID.count == 5, "ID '\(nodeID)' is not 5 chars")
        }
    }

    @Test("Detach throws for non-existent node")
    func detachThrowsNotFound() {
        let editable = makeRefDoc()
        #expect(throws: EditingError.nodeNotFound(id: "missing")) {
            try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "missing")))
        }
    }

    @Test("Detach throws for non-ref node")
    func detachThrowsNotRef() {
        let rect = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let doc = PenDocument(children: [rect])
        let editable = EditableDocument(from: doc)

        #expect(throws: EditingError.notARefNode(id: "r1")) {
            try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "r1")))
        }
    }

    // MARK: - PenID

    @Test("PenID.generate produces 5-char alphanumeric IDs")
    func penIDFormat() {
        for _ in 0 ..< 100 {
            let id = PenID.generate()
            #expect(id.count == 5)
            #expect(id.allSatisfy(\.isLetter) || id.allSatisfy { $0.isLetter || $0.isNumber })
        }
    }

    @Test("PenID.generate avoids collisions with existing set")
    func penIDAvoidCollisions() {
        var existing = Set<String>()
        for _ in 0 ..< 100 {
            let id = PenID.generate(avoiding: existing)
            #expect(!existing.contains(id))
            existing.insert(id)
        }
    }

    // MARK: - Codable

    @Test("DetachRef operation round-trips through Codable")
    func detachCodableRoundTrip() throws {
        let op = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "ref1"))
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)
        #expect(op == decoded)
    }
}
