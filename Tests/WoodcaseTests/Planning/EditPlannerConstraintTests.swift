//
//  EditPlannerConstraintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Value constraints the planner enforces on write.
@MainActor
struct EditPlannerConstraintTests {
    private func refusal(_ intent: EditIntent, at raw: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: raw, in: PlannerFixture.document())
    }

    private func plans(_ intent: EditIntent, at raw: String) throws -> Bool {
        try refusal(intent, at: raw) == nil
    }

    @Test("An opacity of 7 is refused with outOfRange and the expected range")
    func opacityOutOfRange() throws {
        let refusal = try #require(try refusal(.set(["common.opacity": 7]), at: "Board/Row/Flow"))

        #expect(refusal.code == .outOfRange)
        #expect(refusal.property == "common.opacity")
        #expect(refusal.expected == "0 to 1, a fraction")
        #expect(refusal.message.contains("common.opacity"))
        #expect(refusal.message.contains("`"))
    }

    @Test("An opacity override of 7 inside an instance is refused the same way")
    func overrideOpacityOutOfRange() throws {
        let refusal = try #require(try refusal(.override(["opacity": 7]), at: "Board/Chip/Label"))

        #expect(refusal.code == .outOfRange)
        #expect(refusal.property == "opacity")
    }

    @Test("A negative width, corner radius slot or stroke side is refused")
    func negativeSizes() throws {
        #expect(try refusal(.set(["kind.width": -1]), at: "Board/Free")?.code == .outOfRange)
        #expect(try refusal(.set(["kind.cornerRadius": [4, 4, -1, 4]]), at: "Board/Free")?.code == .outOfRange)
        #expect(try refusal(.set(["kind.strokeWidth": ["top": -2]]), at: "Board/Free")?.code == .outOfRange)
    }

    @Test("A font size of 0 and a line height written in points are refused")
    func textMetrics() throws {
        #expect(try refusal(.set(["kind.fontSize": 0]), at: "Board/Row/Caption")?.code == .outOfRange)
        let lineHeight = try #require(try refusal(.set(["kind.lineHeight": 24]), at: "Board/Row/Caption"))
        #expect(lineHeight.code == .outOfRange)
        #expect(lineHeight.expected?.contains("multiple of fontSize") == true)
    }

    @Test("A fractional polygon count is refused with offStep")
    func polygonStep() throws {
        #expect(try refusal(.set(["kind.polygonCount": 4.5]), at: "Board/Shape")?.code == .offStep)
        #expect(try refusal(.set(["kind.polygonCount": 2]), at: "Board/Shape")?.code == .outOfRange)
    }

    @Test("Values inside their ranges plan")
    func inRange() throws {
        #expect(try plans(.set(["common.opacity": 0.4]), at: "Board/Free"))
        #expect(try plans(.set(["kind.width": 0, "kind.cornerRadius": [0, 4, 8, 12]]), at: "Board/Free"))
        #expect(try plans(.set(["kind.lineHeight": 1.4, "kind.fontSize": 12]), at: "Board/Row/Caption"))
        #expect(try plans(.set(["kind.polygonCount": 6]), at: "Board/Shape"))
        #expect(try plans(.set(["kind.width": "fill_container"]), at: "Board/Free"))
    }

    @Test("Writing back an out-of-range value the file already holds is let through")
    func unchangedValuePasses() throws {
        #expect(try plans(.set(["common.opacity": 7]), at: "Board/Free"))
    }

    @Test("Clearing a property with null is never refused")
    func nullPasses() throws {
        #expect(try plans(.set(["common.opacity": nil]), at: "Board/Free"))
    }
}
