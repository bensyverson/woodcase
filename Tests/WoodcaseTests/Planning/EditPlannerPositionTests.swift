//
//  EditPlannerPositionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The planner's refusal of a position layout would ignore.
@MainActor
struct EditPlannerPositionTests {
    private func refusal(_ intent: EditIntent, at raw: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: raw, in: PlannerFixture.document())
    }

    @Test("An x on a child its parent's layout places is refused, suggesting absolute positioning")
    func inFlowSet() throws {
        let refusal = try #require(try refusal(.set(["common.x": 40]), at: "Board/Row/Flow"))

        #expect(refusal.code == .positionIgnoredByLayout)
        #expect(refusal.property == "common.x")
        #expect(refusal.suggestion == "common.layoutPosition=absolute")
        #expect(refusal.message.contains("Board/Row"))
    }

    @Test("An x override on an in-flow node inside an instance is refused")
    func inFlowOverride() throws {
        let refusal = try #require(try refusal(.override(["x": 10]), at: "Board/Chip/Label"))

        #expect(refusal.code == .positionIgnoredByLayout)
        #expect(refusal.property == "x")
        #expect(refusal.suggestion == "layoutPosition=absolute")
    }

    @Test("A y override on an in-flow descendant is refused the same way")
    func inFlowYOverride() throws {
        #expect(try refusal(.override(["y": 10]), at: "Board/Chip/Label")?.code == .positionIgnoredByLayout)
    }

    @Test("Positions layout honors plan")
    func honoredPositions() throws {
        #expect(try refusal(.set(["common.x": 40]), at: "Board/Free") == nil)
        #expect(try refusal(.set(["common.x": 8]), at: "Board/Row/Pinned") == nil)
        #expect(try refusal(.set(["common.x": 8, "common.layoutPosition": "absolute"]), at: "Board/Row/Flow") == nil)
        #expect(try refusal(.override(["x": 4, "layoutPosition": "absolute"]), at: "Board/Chip/Label") == nil)
        #expect(try refusal(.set(["common.x": nil]), at: "Board/Row/Flow") == nil)
    }

    @Test("Making a pinned child flow again while giving it an x is refused")
    func backIntoFlow() throws {
        #expect(try refusal(.set(["common.x": 8, "common.layoutPosition": "auto"]), at: "Board/Row/Pinned")?.code
            == .positionIgnoredByLayout)
    }
}
