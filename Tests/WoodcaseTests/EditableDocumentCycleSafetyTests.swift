//
//  EditableDocumentCycleSafetyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The tree queries, asked about a parent map that has a cycle in it.
///
/// A cycle is never the *settled* state of a document — `applyLocal` refuses a move
/// that would make one, and concurrent moves converge without one. It is reachable
/// *between* operations: ``EditableDocument/applyRemote(_:)`` applies a batch one
/// operation at a time, and a batch that ends acyclic can pass through a state that
/// is not. Every query that walks the parent chain runs during that window — the
/// expansion cache's invalidation rule runs in a `defer` on each mutation — so a
/// walk that trusts the chain to end is an unbounded loop over a growing array.
/// That is not a hang the caller can see: it is an out-of-memory kill.
@MainActor
struct EditableDocumentCycleSafetyTests {
    /// Three frames at the root, with nothing nested.
    private func threeFrames() -> EditableDocument {
        let frames = ["fA", "fB", "fC"].map { id in
            PenNode(
                id: id,
                common: PenNodeCommon(name: id),
                kind: .frame(PenNode.FrameData(children: []))
            )
        }
        return EditableDocument(from: PenDocument(children: frames))
    }

    /// Three frames whose parent map is the cycle fA → fB → fC → fA.
    private func cyclicDocument() -> EditableDocument {
        let document = threeFrames()
        document.parents = ["fA": "fB", "fB": "fC", "fC": "fA"]
        return document
    }

    @Test("ancestors stops at the node that closes a cycle")
    func ancestorsStopAtACycle() {
        let document = cyclicDocument()

        let chain = document.ancestors(of: "fA")

        #expect(chain == ["fB", "fC"])
    }

    @Test("ancestors stops when the chain leads back to the node it started from")
    func ancestorsStopAtASelfParent() {
        let document = threeFrames()
        document.parents = ["fA": "fA"]

        #expect(document.ancestors(of: "fA").isEmpty)
    }

    @Test("isDescendant answers false rather than looping when the chain is a cycle")
    func isDescendantStopsAtACycle() {
        let document = cyclicDocument()

        #expect(!document.isDescendant("fA", of: "fZ"))
    }

    @Test("isDescendant still finds an ancestor that is on the cycle")
    func isDescendantFindsAnAncestorOnTheCycle() {
        let document = cyclicDocument()

        #expect(document.isDescendant("fA", of: "fC"))
    }

    @Test("A three-way concurrent move that passes through a cycle still converges")
    func concurrentMovesThroughACycleTerminate() throws {
        let document = PenDocument(children: ["fA", "fB", "fC"].map { id in
            PenNode(
                id: id,
                common: PenNodeCommon(name: id),
                kind: .frame(PenNode.FrameData(children: []))
            )
        })
        let a = EditableDocument(from: document, peerID: PeerID(rawValue: "aaa"))
        let b = EditableDocument(from: document, peerID: PeerID(rawValue: "bbb"))
        let c = EditableDocument(from: document, peerID: PeerID(rawValue: "ccc"))

        let opsA = try a.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "fA", newParentID: "fB")))
        let opsB = try b.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "fB", newParentID: "fC")))
        let opsC = try c.applyLocal(.moveNode(EditOperation.MoveNode(nodeID: "fC", newParentID: "fA")))

        // The middle of each batch is the cyclic state; applying it must terminate.
        a.applyRemote(opsB + opsC)
        b.applyRemote(opsA + opsC)
        c.applyRemote(opsA + opsB)

        for document in [a, b, c] {
            #expect(document.ancestors(of: "fA").count <= 2)
            #expect(document.ancestors(of: "fB").count <= 2)
            #expect(document.ancestors(of: "fC").count <= 2)
        }
    }
}
