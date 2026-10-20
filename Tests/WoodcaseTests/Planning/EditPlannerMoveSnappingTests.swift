//
//  EditPlannerMoveSnappingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A move that keeps the drawn place can land on whole points
/// (``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``).
@MainActor
struct EditPlannerMoveSnappingTests {
    /// `Plain` and `Other` are unturned free frames; `Chip` sits at a fractional place,
    /// `Fixed` at a whole one, `Bound` has its `x` bound to a variable, `Leaning` is turned.
    private static let json = """
    {
      "version": "2.19",
      "variables": { "gap": { "type": "number", "value": 5 } },
      "children": [
        { "type": "frame", "id": "Plain", "x": 0, "y": 0, "width": 400, "height": 300, "layout": "none",
          "children": [
          { "type": "rectangle", "id": "Chip", "x": 20.4, "y": 30.7, "width": 40, "height": 20 },
          { "type": "rectangle", "id": "Fixed", "x": 240.4, "y": 50, "width": 40, "height": 20 },
          { "type": "rectangle", "id": "Bound", "x": "$gap", "y": 10, "width": 40, "height": 20 },
          { "type": "rectangle", "id": "Leaning", "x": 100, "y": 120, "width": 30, "height": 50, "rotation": 10 }
        ] },
        { "type": "frame", "id": "Other", "x": 100, "y": 100, "width": 400, "height": 300, "layout": "none",
          "children": [] }
      ]
    }
    """

    /// The `common.x`/`common.y` the plan writes to `id`, or `nil` for a key it skips.
    private func plan(
        _ id: String, into parent: String?, by offset: PenPoint, snapping: PlacementSnapping? = nil
    ) throws -> [String: AnyCodable] {
        let document = try WrapFixture.document(Self.json)
        let layout = WrapFixture.layout(of: document)
        let operations = if let snapping {
            try EditPlanner.planMove(
                nodeID: id, into: parent, keepingDrawnPlace: offset, snapping: snapping, in: document, layout: layout
            )
        } else {
            try EditPlanner.planMove(nodeID: id, into: parent, keepingDrawnPlace: offset, in: document, layout: layout)
        }
        for case let .setProperties(write) in operations {
            return write.properties
        }
        return [:]
    }

    @Test("Without the option the drop keeps its fractional place")
    func noneKeepsFractions() throws {
        let writes = try plan("Chip", into: "Other", by: PenPoint(x: 0.3, y: 0.2))
        #expect(writes["common.x"] == .double(-79.3))
    }

    @Test("Whole points round the written x and y in the new parent's space")
    func roundsWrites() throws {
        let writes = try plan("Chip", into: "Other", by: PenPoint(x: 0.3, y: 0.2), snapping: .wholePoints)
        #expect(writes["common.x"] == .int(-79))
        #expect(writes["common.y"] == .int(-69))
    }

    @Test("A stored fractional x the move leaves unchanged is written rounded")
    func roundsUnchangedStored() throws {
        let writes = try plan("Fixed", into: "Plain", by: .zero, snapping: .wholePoints)
        #expect(writes["common.x"] == .int(240))
        #expect(writes["common.y"] == nil)
    }

    @Test("Without the option an unchanged stored coordinate is not written")
    func noneSkipsUnchanged() throws {
        let writes = try plan("Fixed", into: "Plain", by: .zero)
        #expect(writes["common.x"] == nil)
    }

    @Test("A coordinate bound to a variable is written as a number only as without snapping")
    func boundCoordinate() throws {
        let plain = try plan("Bound", into: "Other", by: PenPoint(x: 0.4, y: 0))
        let snapped = try plan("Bound", into: "Other", by: PenPoint(x: 0.4, y: 0), snapping: .wholePoints)
        #expect(plain["common.x"] != nil)
        #expect(snapped["common.x"] == .int(-95))
        #expect(snapped["common.y"] == .int(-90))
    }

    @Test("Rotation is not snapped")
    func rotationUnaffected() throws {
        let document = try WrapFixture.document(Self.json)
        let operations = try EditPlanner.planMove(
            nodeID: "Leaning", into: "Other", keepingDrawnPlace: PenPoint(x: 0.4, y: 0.4), snapping: .wholePoints,
            in: document, layout: WrapFixture.layout(of: document)
        )
        for case let .setProperties(write) in operations {
            #expect(write.properties["common.rotation"] == nil)
        }
        try WrapFixture.apply(operations, to: document)
        #expect(document.node(id: "Leaning")?.common.rotation?.literalValue == 10)
    }
}
