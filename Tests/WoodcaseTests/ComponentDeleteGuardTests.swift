//
//  ComponentDeleteGuardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct ComponentDeleteGuardTests {
    // MARK: - Helpers

    /// A component `comp1` with one text child, plus two instances at root.
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
        let ref1 = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "InstanceA"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let ref2 = PenNode(
            id: "ref2",
            common: PenNodeCommon(name: "InstanceB"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        return PenDocument(children: [component, ref1, ref2])
    }

    private func makeEditable() -> EditableDocument {
        EditableDocument(from: makeDoc())
    }

    // MARK: - Refusal

    @Test("Deleting a component with two instances refuses, naming both")
    func deleteRefusesNamingInstances() {
        let editable = makeEditable()

        #expect(throws: EditingError.componentHasInstances(
            componentID: "comp1",
            instanceIDs: ["ref1", "ref2"]
        )) {
            try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "comp1")))
        }

        // Nothing was removed.
        #expect(editable.nodes["comp1"] != nil)
        #expect(editable.nodes["label"] != nil)
        #expect(editable.rootOrder == ["comp1", "ref1", "ref2"])
    }

    @Test("A refused delete names instances nested inside another component")
    func deleteRefusesNamingNestedInstance() {
        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(name: "Inner"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let outer = PenNode(
            id: "outer",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData(children: [inner]))
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let editable = EditableDocument(from: PenDocument(children: [component, outer]))

        #expect(throws: EditingError.componentHasInstances(
            componentID: "comp1",
            instanceIDs: ["inner"]
        )) {
            try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "comp1")))
        }
    }

    @Test("Deleting a component whose only instance is inside the deleted subtree succeeds")
    func deleteAllowsInstancesInsideTheSubtree() throws {
        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(name: "Inner"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let holder = PenNode(
            id: "holder",
            common: PenNodeCommon(name: "Holder"),
            kind: .frame(PenNode.FrameData(children: [component, inner]))
        )
        let editable = EditableDocument(from: PenDocument(children: [holder]))

        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "holder")))

        #expect(editable.nodes.isEmpty)
        #expect(editable.componentRegistry["comp1"] == nil)
    }

    @Test("Deleting a node with no instances is unaffected by the guard")
    func deletePlainNodeStillWorks() throws {
        let editable = makeEditable()
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "ref1")))
        #expect(editable.nodes["ref1"] == nil)
        #expect(editable.rootOrder == ["comp1", "ref2"])
    }

    // MARK: - Detach

    @Test("Deleting with detach succeeds and leaves both instances as plain frames")
    func deleteWithDetachSucceeds() throws {
        let editable = makeEditable()

        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach)))

        #expect(editable.nodes["comp1"] == nil)
        #expect(editable.nodes["ref1"] == nil)
        #expect(editable.nodes["ref2"] == nil)
        #expect(editable.componentRegistry.isEmpty)

        // Two plain frames remain at root, in the instances' old positions.
        #expect(editable.rootOrder.count == 2)
        for rootID in editable.rootOrder {
            guard let node = editable.nodes[rootID] else {
                Issue.record("Root \(rootID) missing")
                continue
            }
            guard case .frame = node.kind else {
                Issue.record("Root \(rootID) is \(node.kind.typeName), expected a plain frame")
                continue
            }
            #expect(node.common.reusable == nil)
            // The component's text child came along, as an independent node.
            let childIDs = editable.childIDs(of: rootID)
            #expect(childIDs.count == 1)
            if let childID = childIDs.first, case .text = editable.nodes[childID]?.kind {} else {
                Issue.record("Expected a text child under \(rootID)")
            }
        }
        // The detached nodes carry fresh compact IDs, not expansion paths.
        #expect(editable.nodes.keys.allSatisfy { !$0.contains("/") })
    }

    @Test("Detach keeps each instance's name and position")
    func deleteWithDetachKeepsPositions() throws {
        let editable = makeEditable()
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach)))

        let names = editable.rootOrder.map { editable.nodes[$0]?.common.name }
        #expect(names == ["InstanceA", "InstanceB"])
    }

    // MARK: - Inverse

    @Test("Inverse of a detaching delete restores the component and both instances")
    func detachingDeleteInverseRestores() throws {
        let editable = makeEditable()
        let op = EditOperation.DeleteNode(nodeID: "comp1", instances: .detach)

        let partial = try editable.prepareInverse(of: .deleteNode(op))
        let detached = try editable.deleteNode(op)
        let inverse = editable.completeDetachingDeleteInverse(detached: detached, partialInverse: partial)

        #expect(detached.count == 2)
        for step in inverse {
            try editable.apply(step)
        }

        #expect(editable.rootOrder == ["comp1", "ref1", "ref2"])
        #expect(editable.componentRegistry["comp1"] != nil)
        #expect(editable.childIDs(of: "comp1") == ["label"])
        if case .ref = editable.nodes["ref1"]?.kind {} else {
            Issue.record("ref1 was not restored as a ref")
        }
        if case .ref = editable.nodes["ref2"]?.kind {} else {
            Issue.record("ref2 was not restored as a ref")
        }
    }

    // MARK: - CRDT mode

    @Test("A refused delete in CRDT mode leaves both peers untouched")
    func crdtRefuseDoesNotReplicate() throws {
        let doc = makeDoc()
        let peerA = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerB"))

        #expect(throws: EditingError.componentHasInstances(
            componentID: "comp1",
            instanceIDs: ["ref1", "ref2"]
        )) {
            _ = try peerA.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "comp1")))
        }

        #expect(peerA.nodes["comp1"] != nil)
        #expect(peerA.crdtDocument?.tombstones.isEmpty == true)
        #expect(peerA.pendingOperations(since: VectorClock()).isEmpty)
        #expect(peerB.nodes["comp1"] != nil)
    }

    @Test("A detaching delete in CRDT mode converges on a second peer")
    func crdtDetachingDeleteConverges() throws {
        let doc = makeDoc()
        let peerA = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerB"))

        let opsA = try peerA.applyLocal(
            .deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach))
        )
        peerB.applyRemote(opsA)

        #expect(peerA.nodes.keys.sorted() == peerB.nodes.keys.sorted(),
                "Node keys diverged: A=\(peerA.nodes.keys.sorted()), B=\(peerB.nodes.keys.sorted())")
        #expect(peerA.rootOrder == peerB.rootOrder, "rootOrder diverged")
        #expect(peerA.children == peerB.children, "children diverged")
        #expect(peerA.parents == peerB.parents, "parents diverged")

        #expect(peerA.nodes["comp1"] == nil)
        #expect(peerB.nodes["comp1"] == nil)
        #expect(peerB.nodes["ref1"] == nil)
        #expect(peerB.rootOrder.count == 2)
    }

    // MARK: - Codable

    @Test("DeleteNode round-trips its instances policy")
    func deleteNodeCodableRoundTrip() throws {
        let op = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "comp1", instances: .detach))
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(EditOperation.self, from: data)
        #expect(op == decoded)
    }

    @Test("DeleteNode decodes without an instances key, defaulting to refuse")
    func deleteNodeDecodesWithoutInstances() throws {
        let json = Data(#"{"nodeID":"comp1"}"#.utf8)
        let decoded = try JSONDecoder().decode(EditOperation.DeleteNode.self, from: json)
        #expect(decoded == EditOperation.DeleteNode(nodeID: "comp1"))
        #expect(decoded.instances == .refuse)
    }
}
