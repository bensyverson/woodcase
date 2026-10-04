//
//  OpSequencerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The op sequencer's ordering (`project/2026-10-04-three-way-diff-design.md`, algorithm
/// step 5): each case is a change whose operations only apply in the right order.
@MainActor
struct OpSequencerTests {
    private typealias F = MergeFixture

    /// Diffs two documents written as root children and checks the operations turn the
    /// first into the second.
    @discardableResult
    private func expectDiffRebuilds(
        _ from: String, _ to: String, fromRoot: String = "", toRoot: String = ""
    ) throws -> [EditOperation] {
        let source = try F.document(from, root: fromRoot)
        let target = try F.document(to, root: toRoot)
        let operations = DocumentMerge.diff(from: source, to: target)
        for operation in operations {
            try source.apply(operation)
        }
        #expect(source.materialize() == target.materialize())
        return operations
    }

    @Test("A parent and child that swap places are moved without a cycle")
    func swappedNesting() throws {
        try expectDiffRebuilds(
            F.frame("page", F.frame("outer", F.frame("inner", F.rect("leaf")))),
            F.frame("page", F.frame("inner", F.frame("outer", F.rect("leaf"))))
        )
    }

    @Test("Two roots that swap nesting are moved without a cycle")
    func swappedRoots() throws {
        try expectDiffRebuilds(F.frame("a", F.frame("b")), F.frame("b", F.frame("a")))
    }

    @Test("A container becomes a leaf only after its children have left")
    func containerToLeaf() throws {
        try expectDiffRebuilds(
            F.frame("page", F.frame("box", F.rect("a") + "," + F.rect("b"))),
            F.frame("page", F.rect("box") + "," + F.rect("a"))
        )
    }

    @Test("A leaf becomes a container before its children move in")
    func leafToContainer() throws {
        try expectDiffRebuilds(
            F.frame("page", F.rect("box") + "," + F.rect("a")),
            F.frame("page", F.frame("box", F.rect("a") + "," + F.rect("new")))
        )
    }

    @Test("A component with instances that becomes a leaf is retyped in place, its instances kept")
    func componentWithInstancesToLeaf() throws {
        let instance = #"{"type":"ref","id":"r","ref":"C"}"#
        try expectDiffRebuilds(
            F.frame("C", "", #""reusable":true"#) + "," + instance,
            F.rect("C", #""reusable":true"#) + "," + instance
        )
        try expectDiffRebuilds(
            F.frame("C", F.rect("a"), #""reusable":true"#) + "," + instance,
            F.rect("C", #""reusable":true"#) + "," + instance + "," + F.rect("a")
        )
    }

    @Test("A component with instances gets and loses a declared children: []")
    func componentWithInstancesDeclaredChildren() throws {
        let instance = #"{"type":"ref","id":"r","ref":"C"}"#
        try expectDiffRebuilds(
            F.frame("C", nil, #""reusable":true"#) + "," + instance,
            F.frame("C", "", #""reusable":true"#) + "," + instance
        )
        try expectDiffRebuilds(
            F.frame("C", "", #""reusable":true"#) + "," + instance,
            F.frame("C", nil, #""reusable":true"#) + "," + instance
        )
    }

    @Test("Declared-children and leaf retypes are written with updateKind, never by replacing the node")
    func noReplaceSubtree() throws {
        let operations = try expectDiffRebuilds(
            F.frame("page", F.frame("box", "") + "," + F.frame("other", nil)),
            F.frame("page", F.rect("box") + "," + F.frame("other", ""))
        )
        #expect(!operations.contains { if case .replaceSubtree = $0 { true } else { false } })
    }

    @Test("A container's declared children: [] is added and dropped")
    func declaredChildren() throws {
        try expectDiffRebuilds(F.frame("page", F.frame("box", nil)), F.frame("page", F.frame("box", "")))
        try expectDiffRebuilds(F.frame("page", F.frame("box", "")), F.frame("page", F.frame("box", nil)))
        try expectDiffRebuilds(F.frame("page", F.frame("box", F.rect("a"))), F.frame("page", F.frame("box", nil)))
    }

    @Test("A table emptied to {} stays declared, and one dropped is left out, after its entries go")
    func declaredTables() throws {
        let variable = #""variables":{"a":{"type":"number","value":1}}"#
        try expectDiffRebuilds("", "", fromRoot: variable, toRoot: #""variables":{}"#)
        try expectDiffRebuilds("", "", fromRoot: variable, toRoot: "")
        try expectDiffRebuilds("", "", fromRoot: #""themes":{}"#, toRoot: "")
        try expectDiffRebuilds("", "", fromRoot: "", toRoot: #""imports":{}"#)
    }

    @Test("A component deleted with its only instance is deleted after it, whatever their order")
    func componentAndInstanceDeleted() throws {
        let component = F.frame("A", F.rect("A1"), #""reusable":true"#)
        let instance = F.frame("Z", #"{"type":"ref","id":"Zr","ref":"A"}"#)
        try expectDiffRebuilds(component + "," + instance + "," + F.rect("keep"), F.rect("keep"))
        let reversed = F.frame("A", #"{"type":"ref","id":"Ar","ref":"Z"}"#)
        let later = F.frame("Z", F.rect("Z1"), #""reusable":true"#)
        try expectDiffRebuilds(reversed + "," + later + "," + F.rect("keep"), F.rect("keep"))
    }

    @Test("A ref retargeted to a new component is written after the component exists")
    func refRetargetedToNewComponent() throws {
        let old = F.frame("Old", F.rect("O1"), #""reusable":true"#)
        let new = F.frame("New", F.rect("N1"), #""reusable":true"#)
        try expectDiffRebuilds(
            old + "," + #"{"type":"ref","id":"r","ref":"Old"}"#,
            old + "," + #"{"type":"ref","id":"r","ref":"New","descendants":{"N1":{"opacity":0.5}}}"# + "," + new
        )
    }

    @Test("Document additions come first and removals last")
    func documentOrder() throws {
        let operations = try expectDiffRebuilds(
            F.rect("gone"), F.rect("new"),
            fromRoot: #""variables":{"old":{"type":"number","value":1}}"#,
            toRoot: #""variables":{"fresh":{"type":"number","value":2}},"fileToken":"t""#
        )
        guard case .addVariable = operations.first else {
            Issue.record("first op is \(String(describing: operations.first))")
            return
        }
        guard case .removeVariable = operations.last else {
            Issue.record("last op is \(String(describing: operations.last))")
            return
        }
    }

    @Test("Unchanged documents diff to no operations")
    func unchanged() throws {
        let document = F.frame("page", F.frame("box", "") + "," + F.rect("a"))
        #expect(try expectDiffRebuilds(document, document).isEmpty)
    }
}
