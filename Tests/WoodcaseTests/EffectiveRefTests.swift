//
//  EffectiveRefTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What component a `ref` inside an instance actually places, once the instance's
/// own override map has had its say.
///
/// The flat store holds the component's *authored* wiring; an instance may repoint
/// one of its nested refs, and ``PenRefExpander`` honours that. Everything that
/// reads the tree has to agree with the expander, or it looks up a rect that the
/// expansion never produced.
@MainActor
struct EffectiveRefTests {
    private func document(_ fixture: String = "ref-repoint-nested.pen") throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixture)")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Repoints `Tab01` inside the `Sht01` instance at the sibling component.
    private func repoint(_ document: EditableDocument, to componentID: String) throws {
        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Sht01",
            descendantID: "Tab01",
            properties: ["ref": .string(componentID)]
        )))
    }

    @Test("Outside any instance a ref places the component it is authored with")
    func authoredRefWinsOutsideAnInstance() throws {
        let doc = try document()
        #expect(doc.effectiveRefData(of: "Tab01", insideInstances: [])?.ref == "PlnC")
        #expect(doc.componentRootID(placedBy: "Sht01", insideInstances: []) == "ShtC")
    }

    @Test("A node that is not a ref has no ref payload")
    func aPlainNodeHasNoRefPayload() throws {
        let doc = try document()
        #expect(doc.effectiveRefData(of: "Lbl01", insideInstances: []) == nil)
        #expect(doc.componentRootID(placedBy: "Lbl01", insideInstances: []) == nil)
    }

    @Test("Inside an instance that repoints it, a nested ref places the new component")
    func theInstanceOverrideWins() throws {
        let doc = try document()
        try repoint(doc, to: "CurC")

        #expect(doc.effectiveRefData(of: "Tab01", insideInstances: ["Sht01"])?.ref == "CurC")
        #expect(doc.componentRootID(placedBy: "Tab01", insideInstances: ["Sht01"]) == "CurC")
        #expect(doc.effectiveRefData(of: "Tab01", insideInstances: [])?.ref == "PlnC")
    }

    @Test("The expansion and the effective ref agree about what the instance holds")
    func theExpansionAgrees() throws {
        let doc = try document()
        try repoint(doc, to: "CurC")

        let expanded = try doc.expandRef(nodeID: "Sht01").expandedNode
        let ids = Self.ids(in: expanded)
        #expect(ids.contains("Sht01/Tab01/CurC"))
        #expect(ids.contains("Sht01/Tab01/Lbl02"))
        #expect(!ids.contains("Sht01/Tab01/PlnC"))
    }

    @Test("An address inside a repointed instance names the node the expansion made")
    func expandedIDFollowsTheRepoint() throws {
        let doc = try document()
        try repoint(doc, to: "CurC")

        let resolved = try doc.resolve("Sht01/Tab01")
        #expect(resolved == .instanceDescendant(refID: "Sht01", descendantKey: "Tab01"))
        #expect(doc.expandedID(of: resolved) == "Sht01/Tab01/CurC")
        #expect(try doc.resolve("Sht01/Tab01/Lbl02")
            == .instanceDescendant(refID: "Sht01", descendantKey: "Tab01/Lbl02"))
    }

    @Test("The overridable keys of a repointed instance are the new component's")
    func overridableKeysFollowTheRepoint() throws {
        let doc = try document()
        try repoint(doc, to: "CurC")

        let keys = doc.overridableDescendantKeys(ofInstance: "Sht01")
        #expect(keys.contains("Tab01/Lbl02"))
        #expect(!keys.contains("Tab01/Lbl01"))
    }

    @Test("One step settles a nested ref from the payload of the instance it sits in")
    func oneStepFromTheEnclosingPayload() throws {
        let doc = try document()
        try repoint(doc, to: "CurC")
        let sheet = try #require(doc.effectiveRefData(of: "Sht01", insideInstances: []))

        #expect(doc.effectiveRefData(of: "Tab01", enclosedBy: sheet)?.ref == "CurC")
        #expect(doc.effectiveRefData(of: "Tab01", enclosedBy: nil)?.ref == "PlnC")
        #expect(doc.effectiveRefData(of: "Lbl01", enclosedBy: sheet) == nil)
    }

    @Test("A long instance chain is walked, not recursed")
    func aLongChainDoesNotRecurse() throws {
        let doc = try document()
        try repoint(doc, to: "CurC")
        // No document nests this deep; the chain is only long enough that one stack
        // frame per element would overflow a debug build's stack.
        let chain = Array(repeating: "Sht01", count: 200_000)

        #expect(doc.effectiveRefData(of: "Tab01", insideInstances: chain)?.ref == "CurC")
    }

    @Test("A placement follows the alias chain and records every component it passes")
    func placementFollowsAliases() throws {
        let doc = try EditableDocument(from: PenParser.parse(Data(Self.aliasDocument.utf8)))
        let viaAlias = PenNode.RefData(ref: "Alias")

        let placement = try #require(doc.componentPlacement(of: viaAlias, onChain: []))
        #expect(placement.rootID == "CmpA0")
        #expect(placement.chain == ["Alias", "CmpA0"])
        #expect(doc.componentRootID(of: viaAlias) == "CmpA0")
    }

    @Test("A placement stops where the expansion does: at a component already on the chain")
    func placementStopsAtTheChain() throws {
        let doc = try EditableDocument(from: PenParser.parse(Data(Self.aliasDocument.utf8)))

        #expect(doc.componentPlacement(of: PenNode.RefData(ref: "CmpA0"), onChain: ["CmpA0"]) == nil)
        #expect(doc.componentPlacement(of: PenNode.RefData(ref: "Nope0"), onChain: []) == nil)
        // The alias's own target is on the chain, so the expansion clones the alias
        // itself — a ref — and goes no further.
        let stopped = try #require(
            doc.componentPlacement(of: PenNode.RefData(ref: "Alias"), onChain: ["CmpA0"])
        )
        #expect(stopped.rootID == "Alias")
        #expect(stopped.chain == ["Alias", "CmpA0"])
    }

    /// A component, an alias of it, and nothing else.
    private static let aliasDocument = """
    {"version": "2.17", "children": [
      {"id": "CmpA0", "type": "frame", "reusable": true, "width": 100, "height": 100},
      {"id": "Alias", "type": "ref", "reusable": true, "ref": "CmpA0", "x": 200}
    ]}
    """

    /// Every id in an expanded subtree.
    private static func ids(in node: PenNode) -> Set<String> {
        var result: Set<String> = [node.id]
        for child in node.kind.inlineChildren {
            result.formUnion(ids(in: child))
        }
        return result
    }
}
