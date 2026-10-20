//
//  EditPlannerStrokeDashTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a write to `metadata.woodcase.strokeDash` and `strokeDashOffset` is held to: a dash
/// of at most 16 non-negative lengths that are not all zero, an offset that is a number, and
/// never a dash on a per-side stroke, whose bands the dashes cannot flow around (Ben's
/// ruling and the integrator's, 2026-10-14).
@MainActor
struct EditPlannerStrokeDashTests {
    private static let board = """
    {
      "version": "2.19",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 400, "height": 400, "layout": "none",
          "children": [
            { "id": "Rct01", "name": "Card", "type": "rectangle", "width": 100, "height": 60,
              "stroke": "#000000", "strokeWidth": 2 },
            { "id": "Rct02", "name": "Sides", "type": "rectangle", "width": 100, "height": 60,
              "stroke": "#000000", "strokeWidth": { "top": 2, "bottom": 4 } },
            { "id": "Rct03", "name": "Dashed", "type": "rectangle", "width": 100, "height": 60,
              "stroke": "#000000", "strokeWidth": 2,
              "metadata": { "type": "woodcase", "woodcase": { "strokeDash": [8, 4] } } }
          ]
        }
      ]
    }
    """

    private static let dash = PenMetadata.WoodcaseKey.strokeDash.propertyPath
    private static let offset = PenMetadata.WoodcaseKey.strokeDashOffset.propertyPath

    private func refusal(_ properties: [String: AnyCodable], at raw: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(.set(properties), at: raw, in: EditableDocument(from: PenParser.parse(Self.board)))
    }

    @Test("A dash of non-negative lengths, with an offset, plans")
    func wellFormedPlans() throws {
        #expect(try refusal([Self.dash: [8, 4, 0, 4], Self.offset: 2.5], at: "Board/Card") == nil)
    }

    @Test("A negative length, an all-zero dash or more than 16 lengths is out of range",
          arguments: [[-2, 4], [0, 0], Array(repeating: 1, count: 17)] as [[Double]])
    func outOfRange(lengths: [Double]) throws {
        let value = AnyCodable.array(lengths.map { .double($0) })
        let refusal = try #require(try refusal([Self.dash: value], at: "Board/Card"))
        #expect(refusal.code == .outOfRange)
        #expect(refusal.property == Self.dash)
    }

    @Test("A dash that is not an array of numbers, or an offset that is not a number, is the wrong form")
    func wrongForm() throws {
        let dash = try #require(try refusal([Self.dash: "8 4"], at: "Board/Card"))
        #expect(dash.code == .invalidForm)
        #expect(dash.property == Self.dash)
        let offset = try #require(try refusal([Self.offset: "2"], at: "Board/Card"))
        #expect(offset.code == .invalidForm)
        #expect(offset.property == Self.offset)
    }

    @Test("A dash on a per-side stroke is refused")
    func dashOnPerSide() throws {
        let refusal = try #require(try refusal([Self.dash: [8, 4]], at: "Board/Sides"))
        #expect(refusal.code == .dashOnPerSideStroke)
        #expect(refusal.property == Self.dash)
    }

    @Test("Making a dashed stroke per-side is refused, naming the dash to remove")
    func perSideOnDash() throws {
        let refusal = try #require(try refusal(["kind.strokeWidth": ["top": 2, "left": 1]], at: "Board/Dashed"))
        #expect(refusal.code == .dashOnPerSideStroke)
        #expect(refusal.suggestion?.contains("\(Self.dash)=null") == true, "\(String(describing: refusal.suggestion))")
    }

    @Test("Removing the dash while making the stroke per-side plans, and an empty dash is solid")
    func solidOnPerSide() throws {
        let removed = try refusal(["kind.strokeWidth": ["top": 2], Self.dash: .null], at: "Board/Dashed")
        #expect(removed == nil, "\(String(describing: removed))")
        let empty = try refusal([Self.dash: AnyCodable.array([])], at: "Board/Sides")
        #expect(empty == nil, "\(String(describing: empty))")
    }
}
