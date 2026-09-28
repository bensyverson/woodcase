//
//  CRDTDetachConvergenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTDetachConvergenceTests {
    // MARK: - Helpers

    private func makeTwoPeerRefDocs() -> (EditableDocument, EditableDocument) {
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
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let doc = PenDocument(children: [component, refNode])
        let peerA = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerB"))
        return (peerA, peerB)
    }

    // MARK: - Basic CRDT detach convergence

    @Test("Detach via applyLocal produces matching node IDs on both peers")
    func detachNodeIDsConverge() throws {
        let (peerA, peerB) = makeTwoPeerRefDocs()

        let opsA = try peerA.applyLocal(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))
        peerB.applyRemote(opsA)

        // Both peers should have the same node keys (the regression: they used
        // to diverge because processLocal and apply generated different random IDs)
        #expect(peerA.nodes.keys.sorted() == peerB.nodes.keys.sorted(),
                "Node keys diverged: A=\(peerA.nodes.keys.sorted()), B=\(peerB.nodes.keys.sorted())")
        #expect(peerA.rootOrder == peerB.rootOrder, "rootOrder diverged")
        #expect(peerA.children == peerB.children, "children diverged")
        #expect(peerA.parents == peerB.parents, "parents diverged")

        // ref1 should be gone
        #expect(peerA.nodes["ref1"] == nil)
        #expect(peerB.nodes["ref1"] == nil)

        // Expanded nodes should exist with fresh compact IDs (no slashes)
        let newNodes = peerA.nodes.keys.filter { $0 != "comp1" && $0 != "label" }
        for nodeID in newNodes {
            #expect(!nodeID.contains("/"), "Detached node ID '\(nodeID)' contains '/'")
        }
    }

    // MARK: - Peer A detaches while peer B overrides

    @Test("Peer A detaches while peer B overrides — detach wins, override lost")
    func detachWinsOverOverride() throws {
        let (peerA, peerB) = makeTwoPeerRefDocs()

        // Peer A detaches the ref
        let opsA = try peerA.applyLocal(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        // Peer B overrides the ref (before seeing A's detach)
        let opsB = try peerB.applyLocal(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        // Exchange ops
        peerA.applyRemote(opsB)
        peerB.applyRemote(opsA)

        // Both peers should agree that ref1 is gone (tombstoned)
        // Peer A already deleted it; peer B should accept the delete
        #expect(peerA.nodes["ref1"] == nil)
        // Peer B: the ref was deleted remotely, so it should be gone
        #expect(peerB.nodes["ref1"] == nil)
    }

    // MARK: - Peer A detaches while peer B deletes

    @Test("Peer A detaches while peer B deletes — both agree node is gone")
    func detachAndDeleteConverge() throws {
        let (peerA, peerB) = makeTwoPeerRefDocs()

        // Peer A detaches the ref
        let opsA = try peerA.applyLocal(.detachRef(EditOperation.DetachRef(refNodeID: "ref1")))

        // Peer B deletes the ref (before seeing A's detach)
        let opsB = try peerB.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: "ref1")))

        // Exchange ops
        peerA.applyRemote(opsB)
        peerB.applyRemote(opsA)

        // Both peers should agree ref1 is gone
        #expect(peerA.nodes["ref1"] == nil)
        #expect(peerB.nodes["ref1"] == nil)
    }
}
