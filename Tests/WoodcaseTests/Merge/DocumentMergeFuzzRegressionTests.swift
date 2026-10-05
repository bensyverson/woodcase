//
//  DocumentMergeFuzzRegressionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Merges `DocumentMergeFuzzTests` found broken, each cut down to the smallest three
/// documents that show it and named for the seed that found it.
@MainActor
struct DocumentMergeFuzzRegressionTests {
    private typealias F = MergeFixture

    /// Merges three documents written as root children and applies the operations to ours.
    private static func merge(base: String, ours: String, theirs: String) throws -> (MergeResult, EditableDocument) {
        let local = try F.document(ours)
        let result = try DocumentMerge.merge(base: F.document(base), ours: local, theirs: F.document(theirs))
        let merged = EditableDocument(from: local.materialize())
        for operation in result.operations {
            try merged.apply(operation)
        }
        return (result, merged)
    }

    @Test("An instance theirs retypes to a leaf no longer holds the component theirs deletes (disjoint seeds 8, 13)")
    func instanceRetypedAwayFromDeletedComponent() throws {
        let base = F.frame("C", F.rect("c1"), #""reusable":true"#) + "," + #"{"type":"ref","id":"I","ref":"C"}"#
        let theirs = F.rect("I")
        let (result, merged) = try Self.merge(base: base, ours: base, theirs: theirs)
        #expect(result.conflicts.isEmpty)
        #expect(try merged.materialize() == F.document(theirs).materialize())
    }

    @Test("A live override holding a whole Double merges beside theirs' override without tripping the drift check (seed 10006)")
    func liveDoubleOverrideMerges() throws {
        let base = F.frame("C", F.rect("c1") + "," + F.rect("c2"), #""reusable":true"#) + "," + #"{"type":"ref","id":"I","ref":"C"}"#
        let theirs = F.frame("C", F.rect("c1") + "," + F.rect("c2"), #""reusable":true"#) + ","
            + #"{"type":"ref","id":"I","ref":"C","descendants":{"c2":{"opacity":0.8}}}"#
        let ours = try F.document(base)
        try ours.apply(.overrideDescendant(EditOperation.OverrideDescendant(refNodeID: "I", descendantID: "c1", properties: ["opacity": .double(0)])))

        let result = try DocumentMerge.merge(base: F.document(base), ours: ours, theirs: F.document(theirs))
        let merged = EditableDocument(from: ours.materialize())
        for operation in result.operations {
            try merged.apply(operation)
        }
        guard case let .ref(data)? = merged.nodes["I"]?.kind else {
            Issue.record("I is not a ref")
            return
        }
        #expect(data.descendants?["c1"]?.properties["opacity"].map { [.int(0), .double(0)].contains($0) } == true)
        #expect(data.descendants?["c2"]?.properties["opacity"] == .double(0.8))
    }

    @Test("Theirs' extra that ours' kept type models is reported, not written (seed 10483)")
    func extraClaimedByOursTypeIsReported() throws {
        let (result, merged) = try Self.merge(
            base: "",
            ours: #"{"type":"text","id":"n","content":"Hi"}"#,
            theirs: #"{"type":"frame","id":"n","width":250,"content":"Cancel"}"#
        )
        #expect(merged.nodes["n"]?.kind.typeName == "text")
        #expect(result.conflicts.contains { $0.subject == .nodeType(nodeID: "n") && $0.kind == .addedTwice })
        #expect(result.conflicts.contains { $0.subject == .property(nodeID: "n", path: "extras.content") && $0.kind == .addedTwice })
    }

    @Test("Theirs' extra lands on the type theirs gave the node, not the type it had (seed 13697)")
    func extraFollowsTheirsRetype() throws {
        let component = F.frame("C", F.rect("c1"), #""reusable":true"#)
        let (result, merged) = try Self.merge(
            base: component + "," + #"{"type":"ref","id":"I","ref":"C"}"#,
            ours: component + "," + #"{"type":"ref","id":"I","ref":"C","name":"mine"}"#,
            theirs: component + "," + F.rect("I", #""fuzz0":6"#)
        )
        #expect(merged.nodes["I"]?.kind.typeName == "rectangle")
        #expect(merged.nodes["I"]?.extras["fuzz0"] == 6)
        #expect(merged.nodes["I"]?.common.name == "mine")
        #expect(result.conflicts.isEmpty)
    }

    @Test("Theirs' insert into a container ours retyped to a leaf is dropped and reported (seed 1)")
    func insertIntoLocalLeafIsOrphaned() throws {
        let (result, merged) = try Self.merge(
            base: F.frame("P"), ours: F.rect("P"), theirs: F.frame("P", F.rect("n"))
        )
        #expect(merged.nodes["n"] == nil)
        #expect(merged.nodes["P"]?.kind.typeName == "rectangle")
        #expect(result.conflicts.contains { $0.subject == .existence(nodeID: "n") && $0.kind == .orphanedExternalInsert })
    }

    @Test("Theirs' move into a container ours retyped to a leaf keeps ours' parent and is reported")
    func moveIntoLocalLeafKeepsOursParent() throws {
        let (result, merged) = try Self.merge(
            base: F.frame("P") + "," + F.rect("N"),
            ours: F.rect("P") + "," + F.rect("N"),
            theirs: F.frame("P", F.rect("N"))
        )
        #expect(merged.parents["N"] == nil)
        #expect(merged.rootOrder.contains("N"))
        #expect(result.conflicts.contains { $0.subject == .parent(nodeID: "N") })
    }

    @Test("Theirs' move into a local leaf, out of a container theirs deleted, keeps that container")
    func moveIntoLocalLeafKeepsDeletedParent() throws {
        let (result, merged) = try Self.merge(
            base: F.frame("P", F.rect("N")) + "," + F.frame("Q"),
            ours: F.frame("P", F.rect("N")) + "," + F.rect("Q"),
            theirs: F.frame("Q", F.rect("N"))
        )
        #expect(merged.parents["N"] == "P")
        #expect(result.conflicts.contains { $0.subject == .existence(nodeID: "P") && $0.kind == .editedLocallyDeletedExternally })
    }

    @Test("A node ours edited and theirs moved out of a container theirs deleted does not keep that container (seed 10183)")
    func editedNodeMovedOutDoesNotKeepDeletedParent() throws {
        let base = F.frame("A", F.rect("n"))
        let ours = F.frame("A", F.rect("n", #""name":"mine""#))
        let theirs = F.rect("n")
        let (result, merged) = try Self.merge(base: base, ours: ours, theirs: theirs)
        #expect(merged.nodes["A"] == nil)
        #expect(merged.parents["n"] == nil)
        #expect(merged.nodes["n"]?.common.name == "mine")
        #expect(!result.conflicts.contains { $0.subject == .existence(nodeID: "A") })
        let again = try DocumentMerge.merge(base: F.document(base), ours: merged, theirs: F.document(theirs))
        #expect(again.operations.isEmpty)
    }

    @Test("Declining one external move to break a cycle cannot leave another move in a new cycle (seed 11174)")
    func revertedMoveLeavesNoCycle() throws {
        // a and b move under x in theirs; ours moves y, x's parent, under b. Taking both
        // moves makes b → x → y → b; declining b's alone makes a → x → y → b → a.
        let base = F.frame("a", F.frame("b")) + "," + F.frame("y", F.frame("x"))
        let ours = F.frame("a", F.frame("b", F.frame("y", F.frame("x"))))
        let theirs = F.frame("y", F.frame("x", F.frame("a") + "," + F.frame("b")))
        let resolution = try F.resolve(base: base, ours: ours, theirs: theirs)
        let local = try F.document(ours)
        func parent(_ id: String) -> String? {
            resolution.nodes[id].map(\.parentID) ?? local.parents[id]
        }
        for id in ["a", "b", "x", "y"] {
            var seen: Set<String> = [id]
            var cursor = parent(id)
            while let node = cursor, seen.insert(node).inserted {
                cursor = parent(node)
            }
            #expect(cursor == nil, "\(id) sits in a cycle")
        }
    }

    @Test("Ours reordering the children of a container theirs deleted does not keep it (seed 12713)")
    func localReorderDoesNotKeepDeletedContainer() throws {
        let base = F.frame("A", F.rect("b") + "," + F.rect("c"))
        let ours = F.frame("A", F.rect("c") + "," + F.rect("b"))
        let theirs = F.rect("b")
        let (result, merged) = try Self.merge(base: base, ours: ours, theirs: theirs)
        #expect(merged.nodes["A"] == nil)
        #expect(merged.nodes["c"] == nil)
        #expect(merged.rootOrder == ["b"])
        #expect(!result.conflicts.contains { $0.subject == .existence(nodeID: "A") })
        let again = try DocumentMerge.merge(base: F.document(base), ours: merged, theirs: F.document(theirs))
        #expect(again.operations.isEmpty)
    }

    @Test("A container theirs retypes to a leaf keeps ours' type while ours gave it children")
    func localChildrenKeepContainerType() throws {
        let (result, merged) = try Self.merge(
            base: F.frame("P"), ours: F.frame("P", F.rect("n")), theirs: F.rect("P")
        )
        #expect(merged.nodes["P"]?.kind.typeName == "frame")
        #expect(merged.children["P"] == ["n"])
        #expect(result.conflicts.contains { $0.subject == .nodeType(nodeID: "P") && $0.kind == .bothChanged })
    }
}
