//
//  PaintRouteTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

/// Pins which fills an emitter paints as a plain colour and which as layers.
struct PaintRouteTests {
    private static let ramp = PenFill.gradient(PenFill.PenGradientFill(gradientType: .linear))

    @Test("No enabled fill is nothing to paint")
    func none() {
        #expect(PaintRoute(nil) == .none)
        #expect(PaintRoute(.single(.color(.init(enabled: .literal(false), color: .literal("#FF0000"))))) == .none)
    }

    @Test("A lone colour is a solid, a shorthand variable a variable reference")
    func solid() {
        let route = PaintRoute(.single(.shorthand("$ink")))
        #expect(route == .solid(color: .variable("ink"), blendMode: nil))
        #expect(route.plainColor == .variable("ink"))
        #expect(route.layeredFills == nil)
    }

    @Test("A blended solid is layered, since a plain colour cannot carry its blend")
    func blendedSolid() {
        let route = PaintRoute(.single(.color(.init(blendMode: .multiply, color: .literal("#FF0000")))))
        #expect(route.plainColor == nil)
        #expect(route.layeredFills == [.color(.init(blendMode: .multiply, color: .literal("#FF0000")))])
    }

    @Test("A gradient or a stack is painted, disabled fills dropped")
    func painted() {
        let disabled = PenFill.color(.init(enabled: .literal(false), color: .literal("#00FF00")))
        #expect(PaintRoute(.single(Self.ramp)) == .painted([Self.ramp]))
        #expect(PaintRoute(.multiple([disabled, .shorthand("#FF0000"), Self.ramp])) == .painted([.shorthand("#FF0000"), Self.ramp]))
    }
}
