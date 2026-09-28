//
//  ExpansionCacheInvalidationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The expansion cache must survive only the edits that cannot change an
/// expansion. Every test here warms ``EditableDocument/expandRef(nodeID:)``,
/// edits *inside* the component, and then detaches an instance — detach is the
/// reader that turns a stale cache entry into a wrong document.
@MainActor
struct ExpansionCacheInvalidationTests {
    // MARK: - Helpers

    /// A component `comp1` holding one text node `label`, plus an instance `ref1`
    /// and an unrelated rectangle `loose` outside the component.
    private func makeDoc() -> PenDocument {
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
            common: PenNodeCommon(name: "My Button"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let loose = PenNode(
            id: "loose",
            common: PenNodeCommon(name: "Loose"),
            kind: .rectangle(PenNode.RectangleData())
        )
        return PenDocument(children: [component, refNode, loose])
    }

    /// The subtree a detach left behind: the one root that was not there before.
    ///
    /// - Parameters:
    ///   - editable: The document that was detached in.
    ///   - known: The root ids as they stood before the detach.
    /// - Returns: The detached clone, fully materialized.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if no new root appeared.
    private func detachedClone(in editable: EditableDocument, notIn known: Set<String>) throws -> PenNode {
        guard let newRootID = editable.rootOrder.first(where: { !known.contains($0) }) else {
            throw EditingError.nodeNotFound(id: "detached root")
        }
        return try editable.materializeSubtree(rootID: newRootID)
    }

    /// Whether a kind is still an unexpanded `ref`.
    ///
    /// - Parameter kind: The kind to test.
    /// - Returns: `true` for `.ref`.
    private func isRef(_ kind: PenNode.Kind) -> Bool {
        if case .ref = kind {
            return true
        }
        return false
    }

    // MARK: - Local edits inside a component

    @Test("A property edit on a component's descendant reaches a later detach")
    func propertyEditInsideComponent() throws {
        let editable = EditableDocument(from: makeDoc())
        _ = try editable.expandRef(nodeID: "ref1")

        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "label",
            common: PenNodeCommon(name: "Edited")
        )))

        let known = Set(editable.rootOrder)
        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: editable, notIn: known)
        #expect(clone.kind.inlineChildren.map(\.common.name) == ["Edited"])
    }

    @Test("An insert into a component reaches a later detach")
    func insertIntoComponent() throws {
        let editable = EditableDocument(from: makeDoc())
        _ = try editable.expandRef(nodeID: "ref1")

        try editable.apply(.insertNode(EditOperation.InsertNode(
            node: PenNode(
                id: "extra",
                common: PenNodeCommon(name: "Extra"),
                kind: .rectangle(PenNode.RectangleData())
            ),
            parentID: "comp1"
        )))

        let known = Set(editable.rootOrder)
        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: editable, notIn: known)
        #expect(clone.kind.inlineChildren.map(\.common.name) == ["Label", "Extra"])
    }

    @Test("A delete inside a component reaches a later detach")
    func deleteInsideComponent() throws {
        let editable = EditableDocument(from: makeDoc())
        _ = try editable.expandRef(nodeID: "ref1")

        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "label")))

        let known = Set(editable.rootOrder)
        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: editable, notIn: known)
        #expect(clone.kind.inlineChildren.isEmpty)
    }

    @Test("A move out of a component reaches a later detach")
    func moveOutOfComponent() throws {
        let editable = EditableDocument(from: makeDoc())
        _ = try editable.expandRef(nodeID: "ref1")

        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "label", newParentID: nil)))

        let known = Set(editable.rootOrder)
        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: editable, notIn: known)
        #expect(clone.kind.inlineChildren.isEmpty)
    }

    @Test("A move into a component reaches a later detach")
    func moveIntoComponent() throws {
        let editable = EditableDocument(from: makeDoc())
        _ = try editable.expandRef(nodeID: "ref1")

        try editable.apply(.moveNode(EditOperation.MoveNode(nodeID: "loose", newParentID: "comp1")))

        let known = Set(editable.rootOrder)
        try editable.apply(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: editable, notIn: known)
        #expect(clone.kind.inlineChildren.map(\.common.name) == ["Label", "Loose"])
    }

    // MARK: - The reusable flag itself

    @Test("Clearing `reusable` invalidates the refs that expanded through it")
    func clearingReusableInvalidates() throws {
        let editable = EditableDocument(from: makeDoc())
        let expanded = try editable.expandRef(nodeID: "ref1")
        #expect(!isRef(expanded.expandedNode.kind))

        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "comp1",
            common: PenNodeCommon(name: "Button")
        )))

        let after = try editable.expandRef(nodeID: "ref1")
        #expect(isRef(after.expandedNode.kind), "A ref whose component is no longer reusable cannot expand")
    }

    // MARK: - Edits that cannot change an expansion

    @Test("An edit outside every component leaves the cache warm")
    func editOutsideComponentKeepsCache() throws {
        let editable = EditableDocument(from: makeDoc())
        _ = try editable.expandRef(nodeID: "ref1")

        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "loose",
            common: PenNodeCommon(name: "Renamed")
        )))

        #expect(editable.expansionCache?.entries["ref1"] != nil)
    }

    // MARK: - CRDT paths

    @Test("A local CRDT edit inside a component reaches a later detach")
    func crdtLocalEditInsideComponent() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: PeerID(rawValue: "peerA"))
        _ = try editable.expandRef(nodeID: "ref1")

        _ = try editable.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "label",
            common: PenNodeCommon(name: "Edited")
        )))

        let known = Set(editable.rootOrder)
        _ = try editable.applyLocal(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: editable, notIn: known)
        #expect(clone.kind.inlineChildren.map(\.common.name) == ["Edited"])
    }

    @Test("A remote CRDT edit inside a component reaches a later detach")
    func crdtRemoteEditInsideComponent() throws {
        let doc = makeDoc()
        let peerA = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerB"))

        // Peer B warms its cache before peer A's edit arrives.
        _ = try peerB.expandRef(nodeID: "ref1")

        let ops = try peerA.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "label",
            common: PenNodeCommon(name: "Edited")
        )))
        peerB.applyRemote(ops)

        let known = Set(peerB.rootOrder)
        _ = try peerB.applyLocal(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: peerB, notIn: known)
        #expect(clone.kind.inlineChildren.map(\.common.name) == ["Edited"])
    }

    @Test("A remote CRDT insert into a component reaches a later detach")
    func crdtRemoteInsertIntoComponent() throws {
        let doc = makeDoc()
        let peerA = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerB"))

        _ = try peerB.expandRef(nodeID: "ref1")

        let ops = try peerA.applyLocal(.insertNode(EditOperation.InsertNode(
            node: PenNode(
                id: "extra",
                common: PenNodeCommon(name: "Extra"),
                kind: .rectangle(PenNode.RectangleData())
            ),
            parentID: "comp1"
        )))
        peerB.applyRemote(ops)

        let known = Set(peerB.rootOrder)
        _ = try peerB.applyLocal(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        let clone = try detachedClone(in: peerB, notIn: known)
        #expect(clone.kind.inlineChildren.map(\.common.name) == ["Label", "Extra"])
    }
}
