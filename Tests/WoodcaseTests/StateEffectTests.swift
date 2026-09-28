//
//  StateEffectTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

/// The neutral effects a smart-default state carries, before any emitter spells them.
struct StateEffectTests {
    private func effects(_ role: ComponentRole, _ state: String) -> [StateEffect]? {
        RoleStateMapping.smartDefaults(for: role).first { $0.name == state }?.effects
    }

    @Test("Each interaction trigger names its effects")
    func effectsPerTrigger() {
        #expect(RoleStateMapping.smartEffects(for: .hover) == [.dim(brightness: 0.95)])
        #expect(RoleStateMapping.smartEffects(for: .pressed) == [.scale(factor: 0.98)])
        #expect(RoleStateMapping.smartEffects(for: .focused) == [.focusRing(width: 2, offset: 2)])
        #expect(RoleStateMapping.smartEffects(for: .disabled) == [.fade(opacity: 0.5), .ignoresPointer])
    }

    @Test("A button's smart defaults carry their trigger's effects")
    func buttonDefaultsCarryEffects() {
        #expect(effects(.button, "hover") == [.dim(brightness: 0.95)])
        #expect(effects(.button, "pressed") == [.scale(factor: 0.98)])
        #expect(effects(.button, "focused") == [.focusRing(width: 2, offset: 2)])
        #expect(effects(.button, "disabled") == [.fade(opacity: 0.5), .ignoresPointer])
    }

    @Test("A link's active state scales, as a button's pressed state does")
    func linkActiveScales() {
        #expect(effects(.link, "active") == [.scale(factor: 0.98)])
    }

    @Test("Smart defaults hold effects, never property deltas")
    func smartDefaultsHaveNoDeltas() {
        for role in [ComponentRole.button, .link, .toggle, .textInput, .select] {
            for state in RoleStateMapping.smartDefaults(for: role) {
                #expect(state.deltas.isEmpty, "\(role) \(state.name) should carry no deltas")
            }
        }
    }
}
