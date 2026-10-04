//
//  DetachIDPlanTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``: a detach's ids are a function of
/// the ref and the expanded ids — and, in a collaborative session, the replica — so two
/// copies of a document and an inverse prepared before the detach agree on them, two
/// peers never mint the same node, and none reuses an id the document already holds.
@MainActor
struct DetachIDPlanTests {
    private let peerA = PeerID(rawValue: "aaa")

    // MARK: - Helpers

    private func document() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "Comp", "type": "frame", "reusable": true, "children": [
            {"id": "Lbl", "type": "text", "content": "hi"},
            {"id": "Row", "type": "frame", "children": [{"id": "Dot", "type": "ellipse"}]}
          ]},
          {"id": "Holder", "type": "frame", "children": [{"id": "Inst", "type": "ref", "ref": "Comp"}]}
        ]}
        """#)
    }

    private let detach = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "Inst"))

    /// The ids under the holder after the detach, in tree order.
    private func detachedIDs(in editable: EditableDocument) throws -> [String] {
        let root = try #require(editable.children["Holder"]?.first)
        return editable.descendantIDs(of: root)
    }

    // MARK: - The plan itself

    @Test("Each id is five base-62 characters derived from the ref and the expanded id")
    func idsAreDerived() throws {
        let editable = try EditableDocument(from: document())
        let expanded = try editable.expandRef(nodeID: "Inst").expandedNode

        let plan = SubtreeIDPlan.detaching(expanded, refID: "Inst", avoiding: [])
        let again = SubtreeIDPlan.detaching(expanded, refID: "Inst", avoiding: [])

        #expect(plan == again)
        #expect(plan.ids.count == 4)
        #expect(Set(plan.ids).count == 4)
        for id in plan.ids {
            #expect(id.count == 5)
            #expect(id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        }
        #expect(plan.replacements[expanded.id] == plan.ids[0])
    }

    @Test("A different ref yields different ids for the same component")
    func refSaltsTheIDs() throws {
        let editable = try EditableDocument(from: document())
        let expanded = try editable.expandRef(nodeID: "Inst").expandedNode

        let one = SubtreeIDPlan.detaching(expanded, refID: "Inst", avoiding: [])
        let other = SubtreeIDPlan.detaching(expanded, refID: "Other", avoiding: [])
        #expect(Set(one.ids).isDisjoint(with: other.ids))
    }

    @Test("An id the document holds is never reused: the plan re-salts it deterministically")
    func collisionsReSalt() throws {
        let editable = try EditableDocument(from: document())
        let expanded = try editable.expandRef(nodeID: "Inst").expandedNode
        let free = SubtreeIDPlan.detaching(expanded, refID: "Inst", avoiding: [])

        let taken: Set<String> = [free.ids[0], free.ids[2]]
        let salted = SubtreeIDPlan.detaching(expanded, refID: "Inst", avoiding: taken)

        #expect(salted.ids.allSatisfy { !taken.contains($0) })
        #expect(salted.ids[1] == free.ids[1])
        #expect(salted.ids[3] == free.ids[3])
        #expect(salted == SubtreeIDPlan.detaching(expanded, refID: "Inst", avoiding: taken))
    }

    // MARK: - Through the document

    @Test("The same document and ref detach to identical ids in two documents")
    func twoDocumentsAgree() throws {
        let first = try EditableDocument(from: document())
        let second = try EditableDocument(from: document())

        try first.apply(detach)
        try second.apply(detach)

        #expect(try detachedIDs(in: first) == detachedIDs(in: second))
        #expect(first.materialize() == second.materialize())
    }

    @Test("The CRDT path is deterministic per replica, and the plain and CRDT paths of one replica agree")
    func crdtPathIsDeterministicPerReplica() throws {
        let first = try EditableDocument(from: document(), peerID: peerA)
        let second = try EditableDocument(from: document(), peerID: peerA)
        let viaApply = try EditableDocument(from: document(), peerID: peerA)

        _ = try first.applyLocal(detach)
        _ = try second.applyLocal(detach)
        try viaApply.apply(detach)

        #expect(try detachedIDs(in: first) == detachedIDs(in: second))
        #expect(try detachedIDs(in: first) == detachedIDs(in: viaApply))
    }

    @Test("Two peers detaching the same instance concurrently create distinct nodes, and converge")
    func concurrentDetachesConverge() throws {
        let a = try EditableDocument(from: document(), peerID: peerA)
        let b = try EditableDocument(from: document(), peerID: PeerID(rawValue: "bbb"))

        let opsA = try a.applyLocal(detach)
        let opsB = try b.applyLocal(detach)
        #expect(try Set(detachedIDs(in: a)).isDisjoint(with: detachedIDs(in: b)))

        // One peer then deletes its copy; the other's late create must not resurrect it.
        let rootA = try #require(a.children["Holder"]?.first)
        let deleteA = try a.applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: rootA)))
        a.applyRemote(opsB)
        b.applyRemote(opsA + deleteA)

        #expect(a.materialize() == b.materialize())
    }

    @Test("A detach never takes an id the document already holds")
    func detachAvoidsDocumentIDs() throws {
        // Find the ids a free detach would take, then plant a node holding the root's.
        let probe = try EditableDocument(from: document())
        try probe.apply(detach)
        let freeIDs = try detachedIDs(in: probe)

        let editable = try EditableDocument(from: document())
        try editable.apply(.insertNode(EditOperation.InsertNode(
            node: PenNode(id: freeIDs[0], common: PenNodeCommon(name: "Squatter"), kind: .rectangle(PenNode.RectangleData()))
        )))
        let before = Set(editable.nodes.keys)
        try editable.apply(detach)

        let ids = try detachedIDs(in: editable)
        #expect(ids.allSatisfy { !before.contains($0) })
        #expect(editable.node(id: freeIDs[0])?.common.name == "Squatter")
    }
}
