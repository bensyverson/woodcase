//
//  ExpandedIDResolutionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `resolve(expandedID:)` is the inverse of `expandedID(of:)`: an editor holding an id
/// from the expanded tree gets the address the planner takes.
@MainActor
struct ExpandedIDResolutionTests {
    @Test("Every id in the expanded canvas maps to an address that expands back to it",
          arguments: InspectionFixture.roundTrip)
    func everyExpandedIDRoundTrips(fixture: String) throws {
        let document = try InspectionFixture.document(fixture)
        for id in InspectionFixture.ids(in: document.expanded(for: .canvas).children) {
            let resolved = try #require(document.resolve(expandedID: id), "\(id) maps to no address")
            #expect(document.expandedID(of: resolved) == id, "\(id) maps to \(resolved)")
        }
    }

    @Test("Ids inside an imported instance map back too")
    func importedInstanceIDsRoundTrip() throws {
        let document = try InspectionFixture.libraryDocument()
        for id in InspectionFixture.ids(in: document.expanded(for: .canvas).children) {
            let resolved = try #require(document.resolve(expandedID: id), "\(id) maps to no address")
            #expect(document.expandedID(of: resolved) == id, "\(id) maps to \(resolved)")
        }
    }

    @Test("An instance root, a nested instance root and a node below a container each map to their address")
    func eachKindOfID() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        #expect(document.resolve(expandedID: "Page1") == .node(id: "Page1"))
        #expect(document.resolve(expandedID: "Card1/CardC") == .node(id: "Card1"))
        #expect(document.resolve(expandedID: "Card1/Ttl03")
            == .instanceDescendant(refID: "Card1", descendantKey: "Ttl03"))
        #expect(document.resolve(expandedID: "Card1/Btn02/BtnC")
            == .instanceDescendant(refID: "Card1", descendantKey: "Btn02"))
        #expect(document.resolve(expandedID: "Card1/Btn02/Ico02")
            == .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Ico02"))
    }

    @Test("An id the expanded tree does not hold maps to nothing")
    func idsNotInTheTree() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        // An expanded instance never keeps its ref's bare id.
        #expect(document.resolve(expandedID: "Card1") == nil)
        #expect(document.resolve(expandedID: "Nope1") == nil)
        #expect(document.resolve(expandedID: "Card1/Nope1") == nil)
        #expect(document.resolve(expandedID: "") == nil)
        // A name is not an id.
        #expect(document.resolve(expandedID: "Page") == nil)
    }

    @Test("The address it returns is the one the planner writes an override through")
    func addressPlans() throws {
        let document = try InspectionFixture.document(InspectionFixture.nested)
        let target = try #require(document.resolve(expandedID: "Card1/Btn02/Ico02"))

        let plan = try EditPlanner.plan(.override(["kind.fills": "#FF0000"]), at: target, in: document)

        #expect(plan.storage == .instanceOverride)
        #expect(plan.operations == [
            .overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "Card1", descendantID: "Btn02/Ico02", properties: ["fill": "#FF0000"]
            )),
        ])
    }
}
