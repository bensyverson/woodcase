//
//  DetachRecursiveComponentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Detaching an instance of a component that renders itself — directly, or through
/// another component that renders it — and deleting such a component under its
/// instances.
@MainActor
struct DetachRecursiveComponentTests {
    // MARK: - Helpers

    /// `Rc` holds an instance of itself; `Ma` and `Mb` hold an instance of each other;
    /// `Page` holds an instance of each.
    private func document() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "Rc", "type": "frame", "reusable": true, "children": [
            {"id": "RcT", "type": "text", "content": "r"},
            {"id": "RcSelf", "type": "ref", "ref": "Rc"}
          ]},
          {"id": "Ma", "type": "frame", "reusable": true, "children": [
            {"id": "MaT", "type": "text", "content": "a"},
            {"id": "MaB", "type": "ref", "ref": "Mb"}
          ]},
          {"id": "Mb", "type": "frame", "reusable": true, "children": [
            {"id": "MbT", "type": "text", "content": "b"},
            {"id": "MbA", "type": "ref", "ref": "Ma"}
          ]},
          {"id": "Page", "type": "frame", "children": [
            {"id": "IR", "type": "ref", "ref": "Rc"},
            {"id": "IA", "type": "ref", "ref": "Ma"}
          ]}
        ]}
        """#)
    }

    /// Every ref in the document whose component the document does not hold.
    private func danglingRefs(in editable: EditableDocument) -> [String] {
        editable.allNodeIDs.sorted().filter { id in
            guard case let .ref(data)? = editable.nodes[id]?.kind else { return false }
            return editable.nodes[data.ref] == nil
        }
    }

    // MARK: - Deleting under instances

    @Test("Deleting a self-rendering component under .detach leaves no ref to it, and its inverse restores the document")
    func deletingSelfRenderingComponentLeavesNoDanglingRef() throws {
        let editable = try EditableDocument(from: document())
        let before = editable.materialize()
        let op = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "Rc", instances: .detach))
        let inverse = try editable.prepareInverse(of: op)

        try editable.apply(op)

        #expect(danglingRefs(in: editable).isEmpty)
        #expect(editable.nodes["IR"] == nil, "the page's instance is detached")
        // The inverse puts the self-rendering component back, which an edit may no longer
        // do (a component loop); replaying history is what the guard lets through.
        try editable.allowingComponentLoops {
            for step in inverse {
                try editable.apply(step)
            }
        }
        #expect(editable.materialize() == before)
    }

    @Test("Deleting both components of a mutual cycle under .detach leaves no ref to either")
    func deletingMutualCycleLeavesNoDanglingRef() throws {
        let editable = try EditableDocument(from: document())
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Mb", instances: .detach)))
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Ma", instances: .detach)))
        #expect(danglingRefs(in: editable).isEmpty)
    }

    @Test("A collaborative delete of a self-rendering component under .detach leaves no ref to it")
    func collaborativeDeleteLeavesNoDanglingRef() throws {
        let editable = try EditableDocument(from: document(), peerID: PeerID(rawValue: "peer-a"))
        _ = try editable.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "Rc", instances: .detach)))
        #expect(danglingRefs(in: editable).isEmpty)
    }

    @Test("A session's delete of a self-rendering component under .detach undoes exactly")
    func sessionDeleteUndoesExactly() throws {
        let session = try DocumentSession(document: document(), author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")), collaborative: false)
        let before = session.document.materialize()
        try session.submit(.local(LocalEdit(operations: [.deleteNode(EditOperation.DeleteNode(nodeID: "Rc", instances: .detach))])))
        #expect(danglingRefs(in: session.document).isEmpty)
        try session.submit(.undo)
        #expect(session.document.materialize() == before)
    }
}
