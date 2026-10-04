//
//  DetachInverseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditableDocument/prepareInverse(of:)`` is complete for a detach and for a
/// detaching delete *before* either runs: the ids the detach will mint are known in
/// advance, so the inverse names the expanded roots it has to remove, and applying it
/// restores ``EditableDocument/materialize()`` exactly — with no completion step.
@MainActor
struct DetachInverseTests {
    // MARK: - Helpers

    /// A component with two instances on a board, between two siblings, and one
    /// instance that is the only child of its holder.
    private func document() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "children": [
          {"id": "Comp", "type": "frame", "reusable": true, "children": [
            {"id": "Lbl", "type": "text", "content": "hi"}
          ]},
          {"id": "Board", "type": "frame", "children": [
            {"id": "Before", "type": "rectangle"},
            {"id": "InstA", "type": "ref", "ref": "Comp", "name": "A",
             "descendants": {"Lbl": {"content": "a"}}},
            {"id": "After", "type": "rectangle"},
            {"id": "InstB", "type": "ref", "ref": "Comp", "name": "B"}
          ]},
          {"id": "Holder", "type": "frame", "children": [{"id": "InstC", "type": "ref", "ref": "Comp"}]}
        ]}
        """#)
    }

    /// Applies `op` with the inverse prepared beforehand, then the inverse, and checks
    /// the document is back exactly where it was.
    ///
    /// - Returns: The inverse that was applied.
    @discardableResult
    private func roundTrip(_ op: EditOperation, on editable: EditableDocument) throws -> [EditOperation] {
        let before = editable.materialize()
        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        #expect(editable.materialize() != before)
        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.materialize() == before)
        return inverse
    }

    // MARK: - detachRef

    @Test("A detach's inverse removes the expanded root the detach will produce, then restores the ref")
    func detachInverseIsComplete() throws {
        let editable = try EditableDocument(from: document())
        let op = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "InstA"))

        let inverse = try editable.prepareInverse(of: op)
        let result = try editable.detachRef(EditOperation.DetachRef(refNodeID: "InstA"))

        #expect(inverse.count == 2)
        #expect(inverse.first == .deleteNode(EditOperation.DeleteNode(nodeID: result.rootNodeID)))
    }

    @Test("Applying a detach's prepared inverse restores the document exactly")
    func detachRoundTrips() throws {
        try roundTrip(.detachRef(EditOperation.DetachRef(refNodeID: "InstA")), on: EditableDocument(from: document()))
    }

    @Test("A detach of a holder's only child round-trips, empty array and all")
    func detachOnlyChildRoundTrips() throws {
        try roundTrip(.detachRef(EditOperation.DetachRef(refNodeID: "InstC")), on: EditableDocument(from: document()))
    }

    @Test("A detach in collaborative mode round-trips through its prepared inverse")
    func detachRoundTripsInCRDTMode() throws {
        let editable = try EditableDocument(from: document(), peerID: PeerID(rawValue: "aaa"))
        let before = editable.materialize()
        let op = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "InstB"))

        let inverse = try editable.prepareInverse(of: op)
        _ = try editable.applyLocal(op)
        for step in inverse {
            _ = try editable.applyLocal(step)
        }
        #expect(editable.materialize() == before)
    }

    // MARK: - Detaching delete

    @Test("A detaching delete's inverse is complete before the delete and restores the document")
    func detachingDeleteRoundTrips() throws {
        let editable = try EditableDocument(from: document())
        let op = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "Comp", instances: .detach))

        let inverse = try roundTrip(op, on: editable)

        // Restore the component, then for each of the three instances remove its
        // expansion and put the ref back.
        #expect(inverse.count == 7)
    }

    @Test("A detaching delete's inverse names the roots deleteNode returns")
    func detachingDeleteNamesTheRoots() throws {
        let editable = try EditableDocument(from: document())
        let op = EditOperation.DeleteNode(nodeID: "Comp", instances: .detach)

        let inverse = try editable.prepareInverse(of: .deleteNode(op))
        let detached = try editable.deleteNode(op)

        let removed: [String] = inverse.compactMap { step in
            if case let .deleteNode(delete) = step { delete.nodeID } else { nil }
        }
        #expect(Set(removed) == Set(detached.map(\.rootNodeID)))
    }
}
