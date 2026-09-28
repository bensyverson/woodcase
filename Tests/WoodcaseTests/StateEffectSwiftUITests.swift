//
//  StateEffectSwiftUITests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

/// SwiftUI's spelling of each ``StateEffect``: a modifier that takes effect while its
/// state's condition holds, and is the identity otherwise. React's is ``StateEffectCSSTests``.
struct StateEffectSwiftUITests {
    @Test("Each effect is one modifier, the identity while its condition is false", arguments: [
        (StateEffect.dim(brightness: 0.95), ".colorMultiply(Color(white: on ? 0.95 : 1))"),
        (StateEffect.scale(factor: 0.98), ".scaleEffect(on ? 0.98 : 1)"),
        (StateEffect.fade(opacity: 0.5), ".opacity(on ? 0.5 : 1)"),
        (StateEffect.focusRing(width: 2, offset: 2), ".penFocusRing(on, width: 2, offset: 2, cornerRadius: 6)"),
        (StateEffect.ignoresPointer, ".allowsHitTesting(!on)"),
    ])
    func spelling(effect: StateEffect, modifier: String) {
        #expect(effect.swiftUIModifier(when: "on", cornerRadius: 6) == modifier)
    }

    @Test("A condition that is not one term is parenthesized where it is negated")
    func negatedCompoundCondition() {
        #expect(StateEffect.ignoresPointer.swiftUIModifier(when: "variant == .off", cornerRadius: 0)
            == ".allowsHitTesting(!(variant == .off))")
    }
}
