//
//  EditPlannerConnectorQueryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditPlanner/connectorIDs(enclosedBy:in:)``: the connectors a copy of some nodes
/// carries — both ends inside the copied nodes, a copied node or anything inside it (Ben's
/// ruling of 2026-10-23, Penumbra spec §11) — the one rule Copy, Cut, Duplicate and an
/// Option-drag copy share.
@MainActor
struct EditPlannerConnectorQueryTests {
    @Test("Two connected nodes enclose the connectors between them and inside them, not one with an end outside")
    func twoCards() throws {
        let document = try ConnectorFixture.document()

        #expect(EditPlanner.connectorIDs(enclosedBy: ["CardA", "CardB"], in: document) == ["KAB", "KTB"])
    }

    @Test("A container encloses every connector between the nodes inside it, an instance's included")
    func container() throws {
        let document = try ConnectorFixture.document()

        #expect(EditPlanner.connectorIDs(enclosedBy: ["Board"], in: document) == ["KAB", "KTB", "KAC", "KChip"])
    }

    @Test("An end inside a copied instance is enclosed, by its stored id or its expanded root id")
    func instanceEnd() throws {
        let document = try ConnectorFixture.document()
        let rootID = document.expandedID(of: .node(id: "Chip"))

        #expect(EditPlanner.connectorIDs(enclosedBy: ["CardA", "Chip"], in: document) == ["KChip"])
        #expect(EditPlanner.connectorIDs(enclosedBy: ["CardA", rootID], in: document) == ["KChip"])
    }

    @Test("A node drawn inside an instance, given by its expanded id, encloses the end on it")
    func drawnEnd() throws {
        let document = try ConnectorFixture.document()

        #expect(EditPlanner.connectorIDs(enclosedBy: ["Chip/Label", "CardA"], in: document) == ["KChip"])
    }

    @Test("A connector among the given ids is not listed: it is copied already")
    func selectedConnector() throws {
        let document = try ConnectorFixture.document()

        #expect(EditPlanner.connectorIDs(enclosedBy: ["KAB", "CardA", "CardB"], in: document) == ["KTB"])
    }

    @Test("One end alone encloses nothing, and neither do no ids or unknown ids")
    func nothing() throws {
        let document = try ConnectorFixture.document()

        #expect(EditPlanner.connectorIDs(enclosedBy: ["CardB"], in: document).isEmpty)
        #expect(EditPlanner.connectorIDs(enclosedBy: [], in: document).isEmpty)
        #expect(EditPlanner.connectorIDs(enclosedBy: ["Nowhere"], in: document).isEmpty)
    }
}
