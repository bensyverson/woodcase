//
//  StateEffectCSSTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// How React spells each ``StateEffect`` a smart-default state carries.
struct StateEffectCSSTests {
    private func component(
        name: String = "ActionButton",
        role: ComponentRole,
        rotation: PenValue<Double>? = nil,
        states: [StateDefinition]
    ) -> ComponentDefinition {
        ComponentDefinition(
            id: "c1",
            name: name,
            sourceNode: PenNode(
                id: "f1",
                common: PenNodeCommon(name: nil, rotation: rotation),
                kind: .frame(PenNode.FrameData())
            ),
            props: [],
            actions: [],
            bindings: [],
            role: role,
            states: states
        )
    }

    @Test("A button's smart defaults write exactly the CSS they always have")
    func buttonDefaultsByteForByte() {
        let css = StateEmitter.emitCSS(for: [
            component(role: .button, states: RoleStateMapping.smartDefaults(for: .button)),
        ])
        #expect(css == """
        .wc-action-button:hover {
          filter: brightness(0.95);
        }
        .wc-action-button:active {
          transform: scale(0.98);
        }
        .wc-action-button:disabled {
          opacity: 0.5;
          pointer-events: none;
        }
        .wc-action-button:focus-visible {
          outline: 2px solid currentColor;
          outline-offset: 2px;
        }

        """)
    }

    @Test("Every role's smart defaults write exactly the CSS they always have")
    func everyRoleByteForByte() {
        let css = StateEmitter.emitCSS(for: [
            component(name: "Link", role: .link, states: RoleStateMapping.smartDefaults(for: .link)),
            component(name: "Toggle", role: .toggle, states: RoleStateMapping.smartDefaults(for: .toggle)),
            component(name: "Field", role: .textInput, states: RoleStateMapping.smartDefaults(for: .textInput)),
            component(name: "Picker", role: .select, states: RoleStateMapping.smartDefaults(for: .select)),
        ])
        #expect(css == """
        .wc-link:hover {
          filter: brightness(0.95);
        }
        .wc-link:active {
          transform: scale(0.98);
        }
        .wc-link:focus-visible {
          outline: 2px solid currentColor;
          outline-offset: 2px;
        }
        .wc-toggle:disabled {
          opacity: 0.5;
          pointer-events: none;
        }
        .wc-toggle:focus-visible {
          outline: 2px solid currentColor;
          outline-offset: 2px;
        }
        .wc-field:focus-within {
          outline: 2px solid currentColor;
          outline-offset: 2px;
        }
        .wc-field:disabled {
          opacity: 0.5;
          pointer-events: none;
        }
        .wc-picker:focus-within {
          outline: 2px solid currentColor;
          outline-offset: 2px;
        }
        .wc-picker:disabled {
          opacity: 0.5;
          pointer-events: none;
        }

        """)
    }

    private func smartState(
        _ name: String,
        trigger: StateTrigger,
        effects: [StateEffect]
    ) -> StateDefinition {
        StateDefinition(
            name: name,
            trigger: trigger,
            source: .smartDefault,
            isStructural: false,
            deltas: [],
            effects: effects,
            variantNode: nil
        )
    }

    @Test("The emitter spells a state's effects, whatever the state is called")
    func spellsEffectsNotNames() {
        let css = StateEmitter.emitCSS(for: [
            component(role: .button, states: [
                smartState("wiggle", trigger: .hover, effects: [
                    .dim(brightness: 0.8), .fade(opacity: 0.25),
                    .focusRing(width: 1.5, offset: 0), .scale(factor: 1.1), .ignoresPointer,
                ]),
            ]),
        ])
        #expect(css == """
        .wc-action-button:hover {
          filter: brightness(0.8);
          opacity: 0.25;
          outline: 1.5px solid currentColor;
          outline-offset: 0px;
          transform: scale(1.1);
          pointer-events: none;
        }

        """)
    }

    @Test("A state with no effects writes no rule, even one named hover")
    func noEffectsNoRule() {
        let css = StateEmitter.emitCSS(for: [
            component(role: .button, states: [smartState("hover", trigger: .hover, effects: [])]),
        ])
        #expect(css.isEmpty)
    }

    @Test("A rotated root drops only the scale, and says so")
    func rotatedRootDropsOnlyScale() {
        let diagnostics = PenDiagnosticCollector()
        let css = StateEmitter.emitCSS(for: [
            component(role: .button, rotation: .literal(45), states: [
                smartState("pressed", trigger: .pressed, effects: [.scale(factor: 0.98), .fade(opacity: 0.5)]),
            ]),
        ], diagnostics: diagnostics)
        #expect(css == """
        .wc-action-button:active {
          opacity: 0.5;
        }

        """)
        #expect(diagnostics.diagnostics.contains { $0.message.contains("'ActionButton' pressed state") })
    }
}
