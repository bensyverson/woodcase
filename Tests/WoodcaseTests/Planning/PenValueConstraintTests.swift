//
//  PenValueConstraintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The constraint model, and the table that attaches one to each numeric property.
struct PenValueConstraintTests {
    @Test("An inclusive range admits its ends and refuses beyond them")
    func inclusiveRange() {
        let fraction = PenValueConstraint(unit: .fraction, minimum: .inclusive(0), maximum: .inclusive(1))

        #expect(fraction.violation(by: 0) == nil)
        #expect(fraction.violation(by: 1) == nil)
        #expect(fraction.violation(by: -0.1) == .belowMinimum)
        #expect(fraction.violation(by: 7) == .aboveMaximum)
        #expect(fraction.summary == "0 to 1, a fraction")
    }

    @Test("An exclusive minimum refuses the limit itself")
    func exclusiveMinimum() {
        let size = PenValueConstraint(unit: .points, minimum: .exclusive(0))

        #expect(size.violation(by: 0) == .belowMinimum)
        #expect(size.violation(by: 0.5) == nil)
        #expect(size.summary == "> 0, in points")
    }

    @Test("A step refuses a value between steps")
    func step() {
        let count = PenValueConstraint(unit: .count, minimum: .inclusive(3), step: 1)

        #expect(count.violation(by: 4.5) == .offStep)
        #expect(count.violation(by: 5) == nil)
        #expect(count.summary == "whole numbers ≥ 3, a count")
    }

    @Test("A unit alone limits nothing")
    func unitOnly() {
        let degrees = PenValueConstraint(unit: .degrees)

        #expect(!degrees.limitsValues)
        #expect(degrees.violation(by: -720) == nil)
        #expect(degrees.summary == "in degrees")
    }

    @Test("The shape table constrains the properties the format bounds")
    func table() {
        func constraint(_ field: String) -> PenValueConstraint? {
            NodePropertyCodec.shape(of: field)?.constraint
        }

        #expect(constraint("opacity")?.summary == "0 to 1, a fraction")
        #expect(constraint("width")?.minimum == .inclusive(0))
        #expect(constraint("height")?.minimum == .inclusive(0))
        #expect(constraint("cornerRadius")?.minimum == .inclusive(0))
        #expect(constraint("padding")?.minimum == .inclusive(0))
        #expect(constraint("strokeWidth")?.minimum == .inclusive(0))
        #expect(constraint("fontSize")?.minimum == .exclusive(0))
        #expect(constraint("lineHeight")?.unit == .fontSizeMultiple)
        #expect(constraint("innerRadius")?.summary == "0 to 1, a fraction")
        #expect(constraint("sweepAngle")?.summary == "-360 to 360, in degrees")
        #expect(constraint("polygonCount")?.step == 1)
        #expect(constraint("weight")?.summary == "100 to 700, a font weight")
        #expect(constraint("rotation")?.unit == .degrees)
        #expect(constraint("x")?.unit == .points)
        #expect(constraint("content") == nil)
    }

    @Test("A schema row carries its property's constraint")
    func schemaRow() throws {
        let row = try #require(PenSchema.common.properties.first { $0.path == "common.opacity" })

        #expect(row.constraint?.summary == "0 to 1, a fraction")
        #expect(SchemaPropertyReport(row).constraint == "0 to 1, a fraction")
    }
}
