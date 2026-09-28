//
//  CRDTOverrideConvergenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTOverrideConvergenceTests {
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

    // MARK: - CRDT Round-Trip

    @Test("Override operation round-trips via CRDT to peer")
    func overrideCRDTRoundTrip() throws {
        let (peerA, peerB) = makeTwoPeerRefDocs()

        let ops = try peerA.applyLocal(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        peerB.applyRemote(ops)

        // Both peers should have the same override
        guard case let .ref(refA) = peerA.nodes["ref1"]?.kind,
              case let .ref(refB) = peerB.nodes["ref1"]?.kind
        else {
            Issue.record("Expected ref kind on both peers")
            return
        }

        #expect(refA.descendants == refB.descendants)
        #expect(refA.descendants?["label"]?.properties["name"] == .string("OK"))
    }

    @Test("Concurrent overrides on same ref converge via LWW")
    func concurrentOverridesLWW() throws {
        let (peerA, peerB) = makeTwoPeerRefDocs()

        // Peer A overrides label name to "OK"
        let opsA = try peerA.applyLocal(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("OK")]
        )))

        // Peer B overrides label name to "Cancel" (before seeing A's ops)
        let opsB = try peerB.applyLocal(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1",
            descendantID: "label",
            properties: ["name": .string("Cancel")]
        )))

        // Exchange ops
        peerA.applyRemote(opsB)
        peerB.applyRemote(opsA)

        // Both peers should converge on the same value (LWW)
        guard case let .ref(refA) = peerA.nodes["ref1"]?.kind,
              case let .ref(refB) = peerB.nodes["ref1"]?.kind
        else {
            Issue.record("Expected ref kind on both peers")
            return
        }

        #expect(refA.descendants == refB.descendants)
    }
}
