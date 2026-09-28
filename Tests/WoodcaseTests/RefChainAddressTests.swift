//
//  RefChainAddressTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Addresses inside an instance of an *aliased* component — one whose reusable
/// definition is itself a `ref` to another component.
///
/// ``PenRefExpander`` follows that chain and clones its far end, so the instance's
/// expansion holds the last component's nodes. Every reader that names those nodes has
/// to follow the same chain: an instance that expands and prints rows, but refuses
/// every address inside itself, is a dead end.
@MainActor
struct RefChainAddressTests {
    // MARK: - Fixture

    /// `Page2 > ref Inst2 → IconC (reusable ref) → BtnB0 > Lbl04, Grp04 > Ico04`.
    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/addressing-ref-chain.pen")
    }

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: fixtureURL()))
    }

    /// Every id in a subtree, the root's included, in no particular order.
    private func ids(in node: PenNode) -> [String] {
        [node.id] + node.kind.inlineChildren.flatMap(ids(in:))
    }

    // MARK: - What the expander does

    @Test("The expander clones the far end of the chain, prefixed by the instance")
    func expanderClonesTheFarEndOfTheChain() throws {
        let expanded = try PenRefExpander.expand(PenParser.parse(contentsOf: fixtureURL()))
        let found = expanded.children.flatMap(ids(in:))

        #expect(found.contains("Inst2/BtnB0"))
        #expect(found.contains("Inst2/Lbl04"))
        #expect(found.contains("Inst2/Grp04"))
        #expect(found.contains("Inst2/Ico04"))
        #expect(!found.contains("Inst2/IconC"))
    }

    // MARK: - Resolving

    @Test("A node of the aliased component resolves by the id path tree --expand prints")
    func resolvesByIDPath() throws {
        let doc = try document()
        #expect(try doc.resolve("Inst2/Lbl04")
            == .instanceDescendant(refID: "Inst2", descendantKey: "Lbl04"))
        #expect(try doc.resolve("Inst2/Ico04")
            == .instanceDescendant(refID: "Inst2", descendantKey: "Ico04"))
    }

    @Test("A node of the aliased component resolves by name, one segment per container")
    func resolvesByNamePath() throws {
        let doc = try document()
        #expect(try doc.resolve("Page/Primary/Label")
            == .instanceDescendant(refID: "Inst2", descendantKey: "Lbl04"))
        #expect(try doc.resolve("Page/Primary/Stack/Icon")
            == .instanceDescendant(refID: "Inst2", descendantKey: "Ico04"))
    }

    @Test("The instance root's expanded id is the far end of the chain")
    func expandedIDFollowsTheChain() throws {
        let doc = try document()
        #expect(doc.expandedID(of: .node(id: "Inst2")) == "Inst2/BtnB0")
        #expect(doc.expandedID(
            of: .instanceDescendant(refID: "Inst2", descendantKey: "Lbl04")
        ) == "Inst2/Lbl04")
    }

    // MARK: - Naming

    @Test("A node of the aliased component names itself through the chain")
    func namePathFollowsTheChain() throws {
        let doc = try document()
        #expect(doc.namePath(ofDescendant: "Lbl04", in: "Inst2") == "Page/Primary/Label")
        #expect(doc.namePath(ofDescendant: "Ico04", in: "Inst2") == "Page/Primary/Stack/Icon")
    }

    @Test("The name path of a node inside the aliased component resolves back to it")
    func namePathRoundTrips() throws {
        let doc = try document()
        let resolved = ResolvedNodeAddress.instanceDescendant(refID: "Inst2", descendantKey: "Ico04")
        #expect(try doc.resolve(doc.namePath(of: resolved)) == resolved)
    }

    // MARK: - The guard

    @Test("The instance's addressable keys are the far component's nodes")
    func addressableKeysFollowTheChain() throws {
        let doc = try document()
        let keys = doc.addressableDescendantKeys(ofInstance: "Inst2")

        #expect(keys.contains("Lbl04"))
        #expect(keys.contains("Grp04"))
        #expect(keys.contains("Ico04"))
        #expect(!keys.contains("BtnB0"))
    }

    @Test("An override on a node of the aliased component is accepted and reaches the expansion")
    func overrideOnTheAliasedComponentApplies() throws {
        let doc = try document()
        try doc.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Inst2", descendantID: "Lbl04", properties: ["content": .string("Sold")]
        )))

        let rows = try TreeView.rows(
            of: doc, root: "Page2", expandInstances: true, properties: ["kind.content"]
        )
        let label = try #require(rows.first { $0.id == "Inst2/Lbl04" })
        #expect(label.properties?["kind.content"] == .string("Sold"))
    }
}
