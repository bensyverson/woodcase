//
//  EditPlannerLockTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `metadata.woodcase.locked`: what Lock writes, since the format has no lock (Penumbra
/// spec §14, the integrator's ruling of 2026-10-15). Pen keeps the key and ignores it.
@MainActor
struct EditPlannerLockTests {
    private static let locked = PenMetadata.WoodcaseKey.locked.path

    @Test("A boolean is stored in the namespace; anything else is the wrong form")
    func onlyABoolean() throws {
        let document = try WrapFixture.document()
        #expect(PlannerFixture.refusal(.set([Self.locked: "yes"]), at: "#A", in: document)?.code == .invalidForm)
        let address = try #require(NodeAddress("#A"))
        let plan = try EditPlanner.plan(.set([Self.locked: true]), at: address, in: document)
        try WrapFixture.apply(plan.operations, to: document)
        let node = try #require(document.node(id: "A"))
        #expect(node.common.metadata?[woodcase: .locked] == .bool(true))
    }

    @Test("Every node type publishes locked as a schema field, unset meaning unlocked",
          arguments: PenNode.NodeType.allCases)
    func schemaField(type: PenNode.NodeType) throws {
        let row = try #require(PenSchema.field(Self.locked, for: type))
        #expect(row.default == .boolean(false))
        #expect(row.key.written == "metadata.woodcase.locked")
        #expect(PenSchema.woodcaseFields(for: type).map(\.path).contains(Self.locked))
    }
}
