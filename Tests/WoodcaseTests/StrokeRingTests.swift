//
//  StrokeRingTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

/// Pins how far a stroke reaches past the node's box for each alignment.
struct StrokeRingTests {
    private static func ring(_ width: PenStrokeWidth?, _ alignment: PenStrokeAlign?) -> StrokeRing {
        StrokeRing(PenNode.RectangleData(stroke: .single(.shorthand("#000000")), strokeWidth: width, strokeAlignment: alignment))
    }

    private static let reaches: [(PenStrokeAlign?, Double)] = [(.inner, 0), (.center, 2), (nil, 2), (.outer, 4)]

    @Test("A uniform stroke reaches none, half or all of its width past the box", arguments: reaches)
    func uniform(alignment: PenStrokeAlign?, reach: Double) {
        let ring = Self.ring(.uniform(.literal(4)), alignment)
        #expect(ring.widths == EdgeLengths(all: SymbolicLength(points: 4)))
        #expect(ring.outsets == EdgeLengths(all: SymbolicLength(points: reach)))
        #expect(ring.insideWidths == EdgeLengths(all: SymbolicLength(points: 4 - reach)))
    }

    @Test("A per-side stroke leaves an omitted side at zero")
    func perSide() {
        let ring = Self.ring(.perSide(PenStrokeWidth.Sides(top: .literal(2), right: nil, bottom: .literal(6), left: nil)), .outer)
        let expected = EdgeLengths(
            top: SymbolicLength(points: 2), right: .zero, bottom: SymbolicLength(points: 6), left: .zero
        )
        #expect(ring.outsets == expected)
    }

    @Test("An absent width is Pen's default of 1, centred")
    func defaultWidth() {
        let ring = Self.ring(nil, nil)
        #expect(ring.outsets == EdgeLengths(all: SymbolicLength(points: 0.5)))
    }

    @Test("A width bound to a variable keeps the variable, scaled by the reach")
    func variableWidth() {
        let ring = Self.ring(.uniform(.variable("w")), .center)
        let half = SymbolicLength(points: 0, terms: [SymbolicLength.Term(variable: "w", factor: 0.5)])
        #expect(ring.outsets == EdgeLengths(all: half))
    }
}
