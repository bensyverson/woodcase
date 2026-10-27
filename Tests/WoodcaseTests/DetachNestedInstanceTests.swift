//
//  DetachNestedInstanceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Detaching an instance turns it into plain layers with its overrides baked in, and the
/// instances nested inside it stay instances, linked to their components (Ben, 2026-10-27;
/// Penumbra spec §13). The detached instance's overrides on their insides are re-rooted
/// onto them, and connector ends through them follow.
@MainActor
struct DetachNestedInstanceTests {
    private let detachOK = EditOperation.DetachRef(refNodeID: "ok")

    /// The ref payload of a stored node, or `nil`.
    private func refData(_ id: String?, in doc: EditableDocument) -> PenNode.RefData? {
        guard let id, case let .ref(data)? = doc.nodes[id]?.kind else { return nil }
        return data
    }

    // MARK: - Detach

    @Test("a nested instance stays a ref to its component")
    func nestedInstanceStaysRef() throws {
        let doc = try NestedDetachFixture.document()

        let result = try doc.detachRef(detachOK)

        let badge = try #require(result.idMapping["ok/badge"])
        #expect(refData(badge, in: doc)?.ref == "dot")
        #expect(doc.parents[badge] == result.rootNodeID)
        #expect(!NestedDetachFixture.refs(in: doc).values.contains("button"))
    }

    @Test("overrides on a nested instance's insides are re-rooted onto it, nested-of-nested paths included")
    func overridesReRooted() throws {
        let doc = try NestedDetachFixture.document()

        let result = try doc.detachRef(detachOK)

        let descendants = try #require(refData(result.idMapping["ok/badge"], in: doc)?.descendants)
        #expect(Set(descendants.keys) == ["pip", "gem/facet"])
        #expect(descendants["pip"]?.properties["fill"] == .string("#F59E0B"))
        #expect(descendants["gem/facet"]?.properties["fill"] == .string("#22C55E"))
    }

    @Test("overrides on the nested instance's own node are baked onto the ref")
    func overridesOnNestedRefBaked() throws {
        let doc = try NestedDetachFixture.document()

        let result = try doc.detachRef(detachOK)

        let badge = try #require(result.idMapping["ok/badge"])
        #expect(doc.nodes[badge]?.common.opacity == .literal(0.5))
        #expect(refData(badge, in: doc)?.rootOverrides?["width"] != nil)
    }

    @Test("the detached copy draws what the instance drew")
    func drawsTheSame() throws {
        let doc = try NestedDetachFixture.document()

        let result = try doc.detachRef(detachOK)

        let badge = try #require(result.idMapping["ok/badge"])
        #expect(try NestedDetachFixture.fill(of: badge + "/pip", in: doc) == NestedDetachFixture.color("#F59E0B"))
        #expect(try NestedDetachFixture.fill(of: badge + "/gem/facet", in: doc) == NestedDetachFixture.color("#22C55E"))
        let label = try #require(result.idMapping["ok/label"])
        guard case let .text(text)? = doc.nodes[label]?.kind else {
            Issue.record("the label copy is a text")
            return
        }
        #expect(text.content == .literal("Okay"))
    }

    @Test("connector ends through a nested instance path through its copy")
    func connectorEndsFollow() throws {
        let doc = try NestedDetachFixture.document()

        let result = try doc.detachRef(detachOK)

        let badge = try #require(result.idMapping["ok/badge"])
        #expect(NestedDetachFixture.source(of: "KRoot", in: doc) == result.rootNodeID)
        #expect(NestedDetachFixture.source(of: "KPip", in: doc) == badge + "/pip")
        #expect(NestedDetachFixture.source(of: "KFacet", in: doc) == badge + "/gem/facet")
        for id in ["KRoot", "KPip", "KFacet"] {
            let source = try #require(NestedDetachFixture.source(of: id, in: doc))
            #expect(ConnectorFixture.resolves(source, in: doc), "\(id) names a drawn node: \(source)")
        }
    }

    @Test("the prepared inverse puts the instance and its connector ends back exactly")
    func inverseRestores() throws {
        let doc = try NestedDetachFixture.document()
        let before = doc.materialize()
        let inverse = try doc.prepareInverse(of: .detachRef(detachOK))

        try doc.apply(.detachRef(detachOK))
        for operation in inverse {
            try doc.apply(operation)
        }

        #expect(doc.materialize() == before)
    }

    // MARK: - Slot fills

    @Test("instances in a detached instance's slot fill stay refs, with their own overrides")
    func slotFillInstancesStayRefs() throws {
        let doc = try SlotScreenFixture.document()

        let result = try doc.detachRef(EditOperation.DetachRef(refNodeID: "Filled"))

        let row1 = try #require(result.idMapping["Filled/Row1"])
        let row2 = try #require(result.idMapping["Filled/Row2"])
        #expect(refData(row1, in: doc)?.ref == "ItemA")
        #expect(refData(row2, in: doc)?.ref == "ItemB")
        #expect(refData(row2, in: doc)?.descendants?["BLbl"]?.properties["content"] == .string("Second"))
    }

    @Test("an instance in a detached slot fill keeps its own slot fill")
    func slotFillInsideFillKept() throws {
        let doc = try SlotScreenFixture.document()

        let result = try doc.detachRef(EditOperation.DetachRef(refNodeID: "HostInst"))

        let nest = try #require(result.idMapping["HostInst/Nest"])
        #expect(refData(nest, in: doc)?.ref == "Screen")
        #expect(SlotScreenFixture.fillIDs("List", of: nest, in: doc) == ["NRow1"])
    }

    // MARK: - Deleting a component

    @Test("deleting a component detaches its instances one level: nested instances of others stay refs")
    func deleteKeepsOtherNestedInstances() throws {
        let doc = try NestedDetachFixture.document()

        let results = try doc.deleteNode(EditOperation.DeleteNode(nodeID: "button", instances: .detach))

        let result = try #require(results.first)
        let badge = try #require(result.idMapping["ok/badge"])
        #expect(refData(badge, in: doc)?.ref == "dot")
        #expect(refData(badge, in: doc)?.descendants?["pip"]?.properties["fill"] == .string("#F59E0B"))
        #expect(!NestedDetachFixture.refs(in: doc).values.contains("button"))
        #expect(NestedDetachFixture.source(of: "KPip", in: doc) == badge + "/pip")
    }

    @Test("deleting components detaches nested instances of them too, so none is stranded")
    func deleteDetachesNestedInstancesOfDeleted() throws {
        let doc = try NestedDetachFixture.document()

        let results = try doc.deleteNode(EditOperation.DeleteNode(nodeID: "Kit", instances: .detach))

        let result = try #require(results.first)
        let refs = NestedDetachFixture.refs(in: doc)
        #expect(!refs.values.contains("button"))
        #expect(!refs.values.contains("dot"))
        let pip = try #require(result.idMapping["ok/badge/pip"])
        #expect(doc.nodes[pip] != nil)
        let gem = try #require(result.idMapping["ok/badge/gem"])
        #expect(refData(gem, in: doc)?.ref == "jewel")
        #expect(refData(gem, in: doc)?.descendants?["facet"]?.properties["fill"] == .string("#22C55E"))
        #expect(NestedDetachFixture.source(of: "KPip", in: doc) == pip)
        #expect(NestedDetachFixture.source(of: "KFacet", in: doc) == gem + "/facet")
        #expect(try NestedDetachFixture.fill(of: pip, in: doc) == NestedDetachFixture.color("#F59E0B"))
    }

    @Test("a deleting detach's prepared inverse puts everything back exactly")
    func deleteInverseRestores() throws {
        let doc = try NestedDetachFixture.document()
        let before = doc.materialize()
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "Kit", instances: .detach))
        let inverse = try doc.prepareInverse(of: delete)

        try doc.apply(delete)
        for operation in inverse {
            try doc.apply(operation)
        }

        #expect(doc.materialize() == before)
    }
}
