//
//  NodeExtrasPropertyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `extras.<key>` in the ``EditOperation/SetProperties`` vocabulary: a node's
/// unmodeled keys can be set and cleared one at a time, every write has an inverse,
/// a key the model claims is refused, and ``PropertyDiff`` names the keys that differ.
@MainActor
struct NodeExtrasPropertyTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - Helpers

    /// A board carrying one extra, and a ref, so both sides of the rule are in reach.
    private func document() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "Board", "type": "frame", "width": 100, "height": 50, "futureKey": {"a": 1}},
          {"id": "Comp", "type": "frame", "reusable": true},
          {"id": "Inst", "type": "ref", "ref": "Comp"}
        ]}
        """#)
    }

    private func setProperties(_ nodeID: String, _ properties: [String: AnyCodable]) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    // MARK: - Reading

    @Test("An extras path reads the key the file kept, and null for one it did not")
    func readsExtras() throws {
        let board = try #require(EditableDocument(from: document()).node(id: "Board"))
        #expect(try NodePropertyCodec.value(at: "extras.futureKey", of: board) == ["a": 1])
        #expect(try NodePropertyCodec.value(at: "extras.absent", of: board) == .null)
    }

    // MARK: - Set and clear round-trip through apply and inverse

    @Test("Setting a new extra adds it, and its inverse removes it again")
    func setNewExtraRoundTrips() throws {
        let editable = try EditableDocument(from: document())
        let before = editable.materialize()
        let op = setProperties("Board", ["extras.added": .string("x")])

        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        #expect(try #require(editable.node(id: "Board")).extras["added"] == .string("x"))

        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.materialize() == before)
    }

    @Test("Clearing an extra removes the key, and its inverse puts the old value back")
    func clearExtraRoundTrips() throws {
        let editable = try EditableDocument(from: document())
        let before = editable.materialize()
        let op = setProperties("Board", ["extras.futureKey": .null])

        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        #expect(try #require(editable.node(id: "Board")).extras.isEmpty)

        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.materialize() == before)
    }

    @Test("Replacing an extra's value round-trips, alongside an ordinary property")
    func replaceExtraWithOtherPropertyRoundTrips() throws {
        let editable = try EditableDocument(from: document())
        let before = editable.materialize()
        let op = setProperties("Board", ["extras.futureKey": [1, 2], "kind.width": 300])

        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        let board = try #require(editable.node(id: "Board"))
        #expect(board.extras["futureKey"] == [1, 2])
        #expect(try NodePropertyCodec.value(at: "kind.width", of: board) == 300)

        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.materialize() == before)
    }

    // MARK: - Refusals

    @Test("An extras key the node's type claims is refused, and nothing changes")
    func claimedKeyIsRefused() throws {
        let editable = try EditableDocument(from: document())
        let before = editable.materialize()

        #expect(throws: EditingError.unknownProperty(nodeID: "Board", key: "extras.width", nodeType: "frame")) {
            try editable.apply(self.setProperties("Board", ["extras.width": 3]))
        }
        #expect(throws: EditingError.unknownProperty(nodeID: "Board", key: "extras.children", nodeType: "frame")) {
            try editable.apply(self.setProperties("Board", ["extras.children": []]))
        }
        #expect(throws: EditingError.unknownProperty(nodeID: "Board", key: "extras.", nodeType: "frame")) {
            try editable.apply(self.setProperties("Board", ["extras.": 1]))
        }
        #expect(editable.materialize() == before)
    }

    @Test("A ref has no extras — its unclaimed keys are root overrides — so the path is refused")
    func refRefusesExtras() throws {
        let editable = try EditableDocument(from: document())
        #expect(throws: EditingError.unknownProperty(nodeID: "Inst", key: "extras.futureKey", nodeType: "ref")) {
            try editable.apply(self.setProperties("Inst", ["extras.futureKey": 1]))
        }
    }

    @Test("An agent's set cannot write an extra: the authoring check refuses the path")
    func authoredSetRefusesExtras() throws {
        let board = try #require(EditableDocument(from: document()).node(id: "Board"))
        #expect(throws: EditingError.unknownProperty(nodeID: "Board", key: "extras.futureKey", nodeType: "frame")) {
            try NodePropertyCodec.checkAuthored(["extras.futureKey": 2], on: board)
        }
    }

    // MARK: - PropertyDiff

    @Test("PropertyDiff names every extras key that was added, removed or changed")
    func diffExtras() {
        let old = PenExtras(["kept": 1, "changed": 1, "removed": 1])
        let new = PenExtras(["kept": 1, "changed": 2, "added": 1])
        #expect(PropertyDiff.diffExtras(old: old, new: new) == ["extras.changed", "extras.removed", "extras.added"])
        #expect(PropertyDiff.diffExtras(old: old, new: old).isEmpty)
    }

    // MARK: - CRDT

    @Test("In collaborative mode an extras write replicates as the node's whole extras register")
    func crdtReplicatesExtrasAsRegister() throws {
        let source = try document()
        let a = EditableDocument(from: source, peerID: peerA)
        let b = EditableDocument(from: source, peerID: peerB)

        let ops = try a.applyLocal(setProperties("Board", ["extras.added": .string("x"), "kind.width": 120]))
        #expect(ops.contains { op in
            if case let .setProperty(p) = op.payload { p.property == CRDTDocument.extrasProperty } else { false }
        })
        #expect(!ops.contains { op in
            if case let .setProperty(p) = op.payload { p.property.hasPrefix("extras.") } else { false }
        })

        let wire = try JSONDecoder().decode([CRDTOperation].self, from: JSONEncoder().encode(ops))
        b.applyRemote(wire)
        #expect(b.materialize() == a.materialize())
        #expect(try #require(b.node(id: "Board")).extras.values == ["futureKey": ["a": 1], "added": "x"])
    }
}
