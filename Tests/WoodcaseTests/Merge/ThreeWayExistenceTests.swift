//
//  ThreeWayExistenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The three-way merge's existence rules, one per row of the design's table
/// (`project/2026-10-04-three-way-diff-design.md`, algorithm step 3).
@MainActor
struct ThreeWayExistenceTests {
    private typealias F = MergeFixture

    // MARK: - B O ¬T: theirs deleted

    @Test("Theirs deletes a node ours left alone: it is removed")
    func theirsDeletesUntouched() throws {
        let result = try F.resolve(
            base: F.frame("page", "\(F.rect("a")),\(F.rect("b"))"),
            ours: F.frame("page", "\(F.rect("a")),\(F.rect("b"))"),
            theirs: F.frame("page", F.rect("b"))
        )
        #expect(result.removed == ["a"])
        #expect(result.nodes["page"]?.children == ["b"])
        #expect(result.conflicts.isEmpty)
    }

    @Test("Theirs deletes a node ours edited: it is kept with the ancestors theirs deleted, and reported")
    func theirsDeletesEdited() throws {
        let card = { (a: String) in F.frame("card", "\(a),\(F.rect("b"))") }
        let result = try F.resolve(
            base: F.frame("page", card(F.rect("a"))),
            ours: F.frame("page", card(F.rect("a", #""name":"Edited""#))),
            theirs: F.frame("page")
        )
        #expect(result.removed == ["b"], "a sibling ours left alone still goes")
        #expect(result.nodes["card"]?.children == ["a"])
        #expect(result.nodes["page"] == nil, "page keeps card, as ours has it")
        #expect(Set(result.conflicts.map(\.subject)) == [.existence(nodeID: "a"), .existence(nodeID: "card")])
        #expect(result.conflicts.allSatisfy { $0.kind == .editedLocallyDeletedExternally })
    }

    @Test("Theirs deletes a container ours added a child to: it is kept, and reported")
    func theirsDeletesContainerWithLocalChild() throws {
        let result = try F.resolve(
            base: F.frame("page", F.frame("card")),
            ours: F.frame("page", F.frame("card", F.rect("n"))),
            theirs: F.frame("page")
        )
        #expect(result.removed.isEmpty)
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts == [MergeConflict(subject: .existence(nodeID: "card"), kind: .editedLocallyDeletedExternally)])
    }

    @Test("Theirs deletes a container ours only moved a child out of: it is removed")
    func theirsDeletesContainerOursMovedOutOf() throws {
        let result = try F.resolve(
            base: "\(F.frame("page", F.frame("card", F.rect("a")))),\(F.frame("side"))",
            ours: "\(F.frame("page", F.frame("card"))),\(F.frame("side", F.rect("a")))",
            theirs: "\(F.frame("page")),\(F.frame("side"))"
        )
        // theirs deleted card and a; ours moved a out, which is an edit of a, not of card.
        #expect(result.removed == ["card"])
        #expect(result.conflicts == [MergeConflict(subject: .existence(nodeID: "a"), kind: .editedLocallyDeletedExternally)])
    }

    // MARK: - B ¬O T: ours deleted

    @Test("Ours deletes a node theirs left alone: it stays deleted, silently")
    func oursDeletesUntouched() throws {
        let result = try F.resolve(
            base: F.frame("page", "\(F.rect("a")),\(F.rect("b"))"),
            ours: F.frame("page", F.rect("b")),
            theirs: F.frame("page", "\(F.rect("a")),\(F.rect("b"))")
        )
        #expect(result.nodes.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.conflicts.isEmpty)
    }

    @Test("Ours deletes a node theirs edited below: it stays deleted, and the conflict carries theirs' subtree")
    func oursDeletesEdited() throws {
        let base = try F.document(F.frame("page", F.frame("card", F.rect("a"))))
        let ours = try F.document(F.frame("page"))
        let theirs = try F.document(F.frame("page", F.frame("card", F.rect("a", #""name":"Edited""#))))
        var resolver = ThreeWayResolver(base: base, ours: ours, theirs: theirs)
        let result = resolver.run()
        #expect(result.nodes.isEmpty)
        #expect(try result.conflicts == [MergeConflict(
            subject: .existence(nodeID: "card"), kind: .deletedLocallyEditedExternally,
            base: F.subtree("card", of: base), ours: nil, theirs: F.subtree("card", of: theirs)
        )])
    }

    // MARK: - ¬B ¬O T: theirs added

    @Test("Theirs inserts a node: it joins theirs' parent at theirs' place")
    func theirsInserts() throws {
        let theirs = try F.document(F.frame("page", "\(F.rect("a")),\(F.rect("n")),\(F.rect("b"))"))
        var resolver = try ThreeWayResolver(
            base: F.document(F.frame("page", "\(F.rect("a")),\(F.rect("b"))")),
            ours: F.document(F.frame("page", "\(F.rect("a")),\(F.rect("b"))")),
            theirs: theirs
        )
        let result = resolver.run()
        #expect(try result.nodes["n"] == NodeChange.State(node: #require(theirs.nodes["n"]), parentID: "page", children: nil))
        #expect(result.nodes["page"]?.children == ["a", "n", "b"])
        #expect(result.conflicts.isEmpty)
    }

    @Test("A theirs insert into a subtree ours deleted is dropped and reported, with its subtree")
    func theirsInsertsIntoOursDeleted() throws {
        let theirs = try F.document(F.frame("page", F.frame("card", "\(F.rect("a")),\(F.frame("n", F.rect("m")))")))
        var resolver = try ThreeWayResolver(
            base: F.document(F.frame("page", F.frame("card", F.rect("a")))),
            ours: F.document(F.frame("page")),
            theirs: theirs
        )
        let result = resolver.run()
        #expect(result.nodes.isEmpty)
        #expect(try result.conflicts == [MergeConflict(
            subject: .existence(nodeID: "n"), kind: .orphanedExternalInsert, theirs: F.subtree("n", of: theirs)
        )])
    }

    // MARK: - ¬B O T: added twice

    @Test("Both add one id: ours' values stay, theirs-only keys are taken, and differences are reported")
    func addedTwice() throws {
        let result = try F.resolve(
            base: F.frame("page"),
            ours: F.frame("page", F.rect("n", #""name":"A""#)),
            theirs: F.frame("page", F.rect("n", #""name":"B","opacity":0.5"#))
        )
        let merged = try #require(result.nodes["n"])
        #expect(merged.node.common.name == "A")
        #expect(merged.node.common.opacity == .literal(0.5))
        #expect(result.conflicts == [MergeConflict(
            subject: .property(nodeID: "n", path: "common.name"), kind: .addedTwice,
            base: nil, ours: .string("A"), theirs: .string("B")
        )])
    }

    @Test("Both add one id under different parents: ours' parent stays, reported with no base")
    func addedTwiceUnderDifferentParents() throws {
        let result = try F.resolve(
            base: "\(F.frame("left")),\(F.frame("right"))",
            ours: "\(F.frame("left", F.rect("n"))),\(F.frame("right"))",
            theirs: "\(F.frame("left")),\(F.frame("right", F.rect("n")))"
        )
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts == [MergeConflict(
            subject: .parent(nodeID: "n"), kind: .addedTwice,
            base: nil, ours: .string("left"), theirs: .string("right")
        )])
    }

    // MARK: - B O T placement

    @Test("A node theirs moved into a subtree ours deleted goes back to ours' parent, reported")
    func theirsMovesIntoOursDeleted() throws {
        let result = try F.resolve(
            base: F.frame("page", "\(F.rect("a")),\(F.frame("card"))"),
            ours: F.frame("page", F.rect("a")),
            theirs: F.frame("page", F.frame("card", F.rect("a")))
        )
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts == [MergeConflict(
            subject: .parent(nodeID: "a"), kind: .deletedLocallyEditedExternally,
            base: .string("page"), ours: .string("page"), theirs: .string("card")
        )])
    }

    // MARK: - Components

    @Test("A component theirs deleted is kept, whole, for an instance ours added")
    func componentKeptForLocalInstance() throws {
        let component = #"{"type":"frame","id":"comp","reusable":true,"children":[{"type":"text","id":"label","content":"A"}]}"#
        let instance = #"{"type":"ref","id":"inst","ref":"comp"}"#
        let result = try F.resolve(
            base: F.frame("page", "\(component),\(F.rect("x"))"),
            ours: F.frame("page", "\(component),\(F.rect("x")),\(instance)"),
            theirs: F.frame("page", F.rect("x"))
        )
        #expect(result.removed.isEmpty)
        #expect(result.conflicts == [MergeConflict(subject: .existence(nodeID: "comp"), kind: .componentKeptForLocalInstance)])
    }

    @Test("A component theirs deleted with no instance left is removed")
    func componentWithoutInstanceRemoved() throws {
        let component = #"{"type":"frame","id":"comp","reusable":true,"children":[{"type":"text","id":"label","content":"A"}]}"#
        let result = try F.resolve(
            base: F.frame("page", component),
            ours: F.frame("page", component),
            theirs: F.frame("page")
        )
        #expect(result.removed == ["comp", "label"])
        #expect(result.conflicts.isEmpty)
    }

    // MARK: - Identity and type

    @Test("A delete and re-create of one id reads as an edit")
    func recreateIsEdit() throws {
        // theirs' writer dropped node a and wrote a new one under the same id
        let theirs = try F.document(F.frame("page", #"{"type":"rectangle","id":"a","width":20,"height":10}"#))
        var resolver = try ThreeWayResolver(
            base: F.document(F.frame("page", F.rect("a"))),
            ours: F.document(F.frame("page", F.rect("a"))),
            theirs: theirs
        )
        let result = resolver.run()
        #expect(result.removed.isEmpty)
        #expect(result.nodes["a"]?.node == theirs.nodes["a"])
        #expect(result.conflicts.isEmpty)
    }

    @Test("Theirs' type change is taken when ours left every kind key alone")
    func typeChangeTaken() throws {
        let theirs = try F.document(F.frame("page", #"{"type":"ellipse","id":"x","width":10,"height":10}"#))
        var resolver = try ThreeWayResolver(
            base: F.document(F.frame("page", F.rect("x"))),
            ours: F.document(F.frame("page", F.rect("x", #""name":"Mine""#))),
            theirs: theirs
        )
        let result = resolver.run()
        let merged = try #require(result.nodes["x"])
        #expect(merged.node.kind == theirs.nodes["x"]?.kind)
        #expect(merged.node.common.name == "Mine")
        #expect(result.conflicts.isEmpty)
    }

    @Test("Ours' type is kept when ours touched a kind key, and the type change is reported")
    func typeChangeRefused() throws {
        let result = try F.resolve(
            base: F.frame("page", F.rect("x")),
            ours: F.frame("page", #"{"type":"rectangle","id":"x","width":20,"height":10}"#),
            theirs: F.frame("page", #"{"type":"ellipse","id":"x","width":10,"height":10}"#)
        )
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts == [MergeConflict(
            subject: .nodeType(nodeID: "x"), kind: .bothChanged,
            base: .string("rectangle"), ours: .string("rectangle"), theirs: .string("ellipse")
        )])
    }

    // MARK: - Nothing to do

    @Test("A node both deleted, and one only ours added, need nothing")
    func bothDeletedAndOursAdded() throws {
        let result = try F.resolve(
            base: F.frame("page", F.rect("gone")),
            ours: F.frame("page", F.rect("mine")),
            theirs: F.frame("page")
        )
        #expect(result.nodes.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.conflicts.isEmpty)
    }
}
