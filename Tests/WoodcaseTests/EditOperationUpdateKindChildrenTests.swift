//
//  EditOperationUpdateKindChildrenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditOperation/updateKind(_:)`` and a node's child list: a retype to a leaf drops
/// the list it can no longer hold, and ``EditOperation/UpdateKind/emptyChildren`` says
/// whether an empty container writes `"children": []` — each with an inverse.
@MainActor
struct EditOperationUpdateKindChildrenTests {
    private typealias F = MergeFixture

    /// Applies `op`, checks the document reads as `expected`, then applies the inverse
    /// and checks it is back where it started.
    private func roundTrip(_ op: EditOperation, on document: EditableDocument, expecting expected: EditableDocument) throws {
        let before = document.materialize()
        let inverse = try document.prepareInverse(of: op)
        try document.apply(op)
        #expect(document.materialize() == expected.materialize())
        // The flat store, not only the file: a leaf keeps no child list behind.
        #expect(document.children == expected.children)
        for step in inverse {
            try document.apply(step)
        }
        #expect(document.materialize() == before)
    }

    private func updateKind(_ id: String, _ kind: PenNode.Kind, _ empty: EditOperation.UpdateKind.EmptyChildren? = nil) -> EditOperation {
        .updateKind(EditOperation.UpdateKind(nodeID: id, kind: kind, emptyChildren: empty))
    }

    private func kind(of id: String, in json: String) throws -> PenNode.Kind {
        try #require(F.document(json).nodes[id]).kind
    }

    @Test("A container declaring children: [] retyped to a leaf drops the list, and the inverse restores it")
    func leafRetypeDropsDeclaredList() throws {
        let document = try F.document(F.frame("box", ""))
        let target = try F.document(F.rect("box"))
        let kind = try #require(target.nodes["box"]).kind
        try roundTrip(updateKind("box", kind), on: document, expecting: target)
        #expect(document.children["box"] == [])
    }

    @Test("A reusable component with instances retyped to a leaf keeps its instances")
    func componentRetypedToLeaf() throws {
        let instance = #"{"type":"ref","id":"r","ref":"C"}"#
        let document = try F.document(F.frame("C", "", #""reusable":true"#) + "," + instance)
        let target = try F.document(F.rect("C", #""reusable":true"#) + "," + instance)
        let kind = try #require(target.nodes["C"]).kind
        try roundTrip(updateKind("C", kind), on: document, expecting: target)
    }

    @Test("A container that still holds children is not retyped to a leaf")
    func leafRetypeWithChildrenRefused() throws {
        let document = try F.document(F.frame("box", F.rect("a")))
        let before = document.materialize()
        #expect(throws: EditingError.cannotHaveChildren(parentID: "box")) {
            try document.apply(self.updateKind("box", self.kind(of: "x", in: F.rect("x"))))
        }
        #expect(document.materialize() == before)
    }

    @Test("emptyChildren declares an empty list, and drops one, each with an inverse")
    func emptyChildrenDeclaresAndDrops() throws {
        let frameKind = try kind(of: "box", in: F.frame("box", nil))
        try roundTrip(
            updateKind("box", frameKind, .declared),
            on: F.document(F.frame("box", nil)), expecting: F.document(F.frame("box", ""))
        )
        try roundTrip(
            updateKind("box", frameKind, .absent),
            on: F.document(F.frame("box", "")), expecting: F.document(F.frame("box", nil))
        )
    }

    @Test("A leaf retyped to a container can declare its empty list in the same operation")
    func leafToDeclaredContainer() throws {
        try roundTrip(
            updateKind("box", kind(of: "box", in: F.frame("box", nil)), .declared),
            on: F.document(F.rect("box")), expecting: F.document(F.frame("box", ""))
        )
    }

    @Test("emptyChildren leaves a list that holds children alone")
    func emptyChildrenIgnoresPopulatedList() throws {
        let document = try F.document(F.frame("box", F.rect("a")))
        try document.apply(updateKind("box", kind(of: "box", in: F.frame("box", nil)), .absent))
        #expect(document.children["box"] == ["a"])
    }

    @Test("A leaf kind cannot declare children")
    func leafCannotDeclare() throws {
        let document = try F.document(F.rect("box"))
        #expect(throws: EditingError.cannotHaveChildren(parentID: "box")) {
            try document.apply(self.updateKind("box", self.kind(of: "box", in: F.rect("box")), .declared))
        }
    }

    @Test("emptyChildren round-trips through the JSON encoding, and an op without it still decodes")
    func codable() throws {
        let op = try updateKind("box", kind(of: "box", in: F.frame("box", nil)), .declared)
        #expect(try JSONDecoder().decode(EditOperation.self, from: JSONEncoder().encode(op)) == op)
        let plain = try updateKind("box", kind(of: "box", in: F.frame("box", nil)))
        #expect(try JSONDecoder().decode(EditOperation.self, from: JSONEncoder().encode(plain)) == plain)
    }

    @Test("Normalizing keeps an updateKind whole when it changes the declaration")
    func normalizedKeepsDeclaration() throws {
        let document = try F.document(F.frame("box", nil))
        let op = try updateKind("box", kind(of: "box", in: F.frame("box", nil)), .declared)
        #expect(op.normalized(in: document) == op)
    }
}
