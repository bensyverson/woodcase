//
//  NodeInspectionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `inspect(expandedID:)`: an expanded id's address, where its values come from, and
/// which properties the instance overrides there.
@MainActor
struct NodeInspectionTests {
    // MARK: - Address and overrides

    @Test("A nested instance's descendant reports its address, its definition and the instance's override")
    func nestedDescendant() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let inspection = try #require(document.inspect(expandedID: "Card1/Btn02/Lbl02"))

        #expect(inspection.expandedID == "Card1/Btn02/Lbl02")
        #expect(inspection.address == .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Lbl02"))
        #expect(inspection.source == .componentNode(definitionID: "Lbl02"))
        #expect(inspection.sourceNode?.id == "Lbl02")
        #expect(inspection.overriddenPaths == ["kind.content"])
        #expect(inspection.overrides == [
            NodeInspection.Override(key: "content", path: "kind.content", value: "Buy"),
        ])
        #expect(inspection.isOverridden("kind.content"))
        #expect(inspection.isOverridden("content"))
        #expect(!inspection.isOverridden("kind.fills"))
    }

    @Test("A descendant the instance does not override reports no overrides")
    func unoverriddenDescendant() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let inspection = try #require(document.inspect(expandedID: "Card1/Btn02/Ico02"))

        #expect(inspection.source == .componentNode(definitionID: "Ico02"))
        #expect(inspection.overrides.isEmpty)
    }

    @Test("The source node is the definition as stored, not as the instance shows it")
    func sourceNodeIsUnpatched() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let inspection = try #require(document.inspect(expandedID: "Card1/Ttl03"))

        let source = try #require(inspection.sourceNode)
        #expect(try NodePropertyCodec.value(at: "kind.content", of: source) == "Card")
        #expect(inspection.overriddenPaths == ["kind.content"])
    }

    @Test("A nested instance root inside an instance is a component node with the outer instance's key")
    func nestedInstanceRoot() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let inspection = try #require(document.inspect(expandedID: "Card1/Btn02/BtnC"))

        #expect(inspection.address == .instanceDescendant(refID: "Card1", descendantKey: "Btn02"))
        #expect(inspection.source == .componentNode(definitionID: "Btn02"))
    }

    // MARK: - Instance roots

    @Test("An instance root reports its component and the root overrides it stores")
    func instanceRoot() throws {
        let document = try InspectionFixture.document("planner.pen")
        try InspectionFixture.write(.override(["kind.fills": "#00FF00"]), at: .node(id: "Chi01"), in: document)

        let inspection = try #require(document.inspect(expandedID: "Chi01/Cmp01"))

        #expect(inspection.address == .node(id: "Chi01"))
        #expect(inspection.source == .instance(componentID: "Cmp01"))
        #expect(inspection.sourceNode?.id == "Cmp01")
        #expect(inspection.overriddenPaths == ["kind.fills"])
        #expect(inspection.overrides.first?.key == "fill")
    }

    @Test("A ref whose component is missing is an instance with no component")
    func brokenInstance() throws {
        let document = try InspectionFixture.document("planner.pen")
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Chi01", properties: ["kind.ref": "Gone1"]
        )))

        let inspection = try #require(document.inspect(expandedID: "Chi01"))

        #expect(inspection.source == .instance(componentID: nil))
        #expect(inspection.sourceNode == nil)
    }

    // MARK: - Nodes of their own

    @Test("A node with storage of its own is its own source and has no overrides")
    func ownStorage() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let inspection = try #require(document.inspect(expandedID: "Page1"))

        #expect(inspection.address == .node(id: "Page1"))
        #expect(inspection.source == .ownStorage)
        #expect(inspection.sourceNode?.id == "Page1")
        #expect(inspection.overrides.isEmpty)
    }

    @Test("An id the expanded tree does not hold has no inspection")
    func unknownID() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        #expect(document.inspect(expandedID: "Card1") == nil)
        #expect(document.inspect(.node(id: "Nope1")) == nil)
    }

    // MARK: - Slots

    @Test("Content an instance wrote into a slot is slot content, with no overrides")
    func slotContent() throws {
        let document = try InspectionFixture.document(InspectionFixture.slotFill)
        let inspection = try #require(document.inspect(expandedID: "Inst0/Note0"))

        #expect(inspection.address == .instanceDescendant(refID: "Inst0", descendantKey: "Note0"))
        #expect(inspection.source == .slotContent)
        #expect(inspection.sourceNode?.id == "Note0")
        #expect(inspection.overrides.isEmpty)
    }

    @Test("A filled slot reports its children override under a key that is no property")
    func filledSlot() throws {
        let document = try InspectionFixture.document(InspectionFixture.slotFill)
        let inspection = try #require(document.inspect(expandedID: "Inst0/CSlt0"))

        #expect(inspection.source == .componentNode(definitionID: "CSlt0"))
        #expect(inspection.overrides.map(\.key) == ["children"])
        #expect(inspection.overrides.map(\.path) == [nil])
        #expect(inspection.overriddenPaths.isEmpty)
    }

    // MARK: - Round trip through the planner

    @Test("An override planned at the inspected address is listed, and resetting it clears it")
    func overrideAndResetRoundTrip() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let address = try #require(document.inspect(expandedID: "Card1/Btn02/Ico02")).address

        try InspectionFixture.write(.override(["kind.fills": "#FF0000", "common.opacity": 0.5]), at: address, in: document)
        let overridden = try #require(document.inspect(expandedID: "Card1/Btn02/Ico02"))
        #expect(overridden.overriddenPaths == ["common.opacity", "kind.fills"])

        try InspectionFixture.write(.resetOverride(overridden.overriddenPaths), at: address, in: document)
        #expect(document.inspect(expandedID: "Card1/Btn02/Ico02")?.overrides.isEmpty == true)
    }
}
