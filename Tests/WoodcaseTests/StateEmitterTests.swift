//
//  StateEmitterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct StateEmitterTests {
    // MARK: - Helpers

    private func makeFrame(
        id: String = "f1",
        name: String? = nil,
        rotation: PenValue<Double>? = nil,
        fills: PenFills? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, rotation: rotation),
            kind: .frame(PenNode.FrameData(fills: fills, children: children))
        )
    }

    // MARK: - cssClassName

    @Test("cssClassName converts PascalCase to kebab with wc- prefix")
    func cssClassNameBasic() {
        #expect(StateEmitter.cssClassName(for: "ActionButton") == "wc-action-button")
    }

    @Test("cssClassName handles single word")
    func cssClassNameSingle() {
        #expect(StateEmitter.cssClassName(for: "Button") == "wc-button")
    }

    @Test("cssClassName handles multiple capitals")
    func cssClassNameMultipleCaps() {
        #expect(StateEmitter.cssClassName(for: "MyUIToggle") == "wc-my-ui-toggle")
    }

    // MARK: - cssVarName

    @Test("cssVarName for root node uses simple name")
    func cssVarNameRoot() {
        let name = StateEmitter.cssVarName(
            className: "wc-action-button", nodePath: ".", property: .fills
        )
        #expect(name == "--wc-action-button-bg")
    }

    @Test("cssVarName for non-root node includes path segment")
    func cssVarNameNonRoot() {
        let name = StateEmitter.cssVarName(
            className: "wc-action-button", nodePath: "Background", property: .fills
        )
        #expect(name == "--wc-action-button-background-bg")
    }

    @Test("cssVarName for nested non-root path uses last segment")
    func cssVarNameNestedPath() {
        let name = StateEmitter.cssVarName(
            className: "wc-action-button", nodePath: "Header/Title", property: .textColor
        )
        #expect(name == "--wc-action-button-title-color")
    }

    @Test("cssVarName maps all DeltaProperty values to CSS suffixes")
    func cssVarNameAllProperties() {
        let cn = "wc-btn"
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .fills) == "--wc-btn-bg")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .textColor) == "--wc-btn-color")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .cornerRadius) == "--wc-btn-radius")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .opacity) == "--wc-btn-opacity")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .fontSize) == "--wc-btn-font-size")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .fontWeight) == "--wc-btn-font-weight")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .width) == "--wc-btn-width")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .height) == "--wc-btn-height")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .padding) == "--wc-btn-padding")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .gap) == "--wc-btn-gap")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .strokeColor) == "--wc-btn-border-color")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .shadow) == "--wc-btn-shadow")
        #expect(StateEmitter.cssVarName(className: cn, nodePath: ".", property: .blur) == "--wc-btn-filter")
    }

    // MARK: - stateAffectedProperties

    @Test("stateAffectedProperties returns correct mapping for fill changes")
    func stateAffectedPropertiesFills() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let affected = StateEmitter.stateAffectedProperties(for: component)
        #expect(affected["."] == [.fills])
    }

    @Test("stateAffectedProperties ignores smart defaults")
    func stateAffectedPropertiesIgnoresSmartDefaults() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .hover),
                    variantNode: nil
                ),
            ]
        )

        let affected = StateEmitter.stateAffectedProperties(for: component)
        #expect(affected.isEmpty)
    }

    // MARK: - emitCSS

    @Test("emitCSS with single hover fill override produces base + :hover rules")
    func emitCSSSingleHoverFill() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(fills: .single(.shorthand("#007AFF"))),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains(".wc-action-button {"))
        #expect(css.contains("--wc-action-button-bg: #007AFF"))
        #expect(css.contains(".wc-action-button:hover {"))
        #expect(css.contains("--wc-action-button-bg: #0051D5"))
    }

    @Test("emitCSS with multiple states produces multiple rule blocks")
    func emitCSSMultipleStates() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(fills: .single(.shorthand("#007AFF"))),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
                StateDefinition(
                    name: "pressed",
                    trigger: .pressed,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#003DA5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains(".wc-action-button:hover {"))
        #expect(css.contains(".wc-action-button:active {"))
    }

    @Test("emitCSS smart defaults produce direct CSS properties")
    func emitCSSSmartDefaults() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .hover),
                    variantNode: nil
                ),
                StateDefinition(
                    name: "pressed",
                    trigger: .pressed,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .pressed),
                    variantNode: nil
                ),
                StateDefinition(
                    name: "focused",
                    trigger: .focused,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .focused),
                    variantNode: nil
                ),
                StateDefinition(
                    name: "disabled",
                    trigger: .disabled,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .disabled),
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains("filter: brightness(0.95)"))
        #expect(css.contains("transform: scale(0.98)"))
        #expect(css.contains("outline: 2px solid currentColor"))
        #expect(css.contains("opacity: 0.5"))
        #expect(css.contains("pointer-events: none"))
    }

    @Test("emitCSS with data-attribute trigger uses attribute selector")
    func emitCSSDataAttributeTrigger() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Toggle",
            sourceNode: makeFrame(fills: .single(.shorthand("#CCC"))),
            props: [],
            actions: [],
            bindings: [],
            role: .toggle,
            states: [
                StateDefinition(
                    name: "on",
                    trigger: .attribute(name: "enabled", value: "true"),
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#34C759")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains("[data-enabled=\"true\"]"))
    }

    @Test("emitCSS with transform conflict skips transform smart default")
    func emitCSSTransformConflict() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(rotation: .literal(45)),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "pressed",
                    trigger: .pressed,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .pressed),
                    variantNode: nil
                ),
            ]
        )

        let diagnostics = PenDiagnosticCollector()
        let css = StateEmitter.emitCSS(for: [component], diagnostics: diagnostics)
        #expect(!css.contains("transform: scale"))
        #expect(diagnostics.diagnostics.contains { $0.message.contains("transform") })
    }

    @Test("emitCSS resolves a transform override's base value from the node's own rotation, not the state's")
    func emitCSSTransformOverrideBaseValue() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(rotation: .literal(10)),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "disabled",
                    trigger: .disabled,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(transform: DeltaTransform(rotation: 20, flipX: false, flipY: false)),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains(".wc-action-button {\n  --wc-action-button-transform: rotate(-10deg);\n}"))
        #expect(css.contains(".wc-action-button:disabled {\n  --wc-action-button-transform: rotate(-20deg);\n}"))
    }

    @Test("emitCSS writes `none` as the base value for a transform override on an unrotated, unflipped node")
    func emitCSSTransformOverrideEmptyBase() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "disabled",
                    trigger: .disabled,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(transform: DeltaTransform(rotation: nil, flipX: true, flipY: false)),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains(".wc-action-button {\n  --wc-action-button-transform: none;\n}"))
        #expect(css.contains(".wc-action-button:disabled {\n  --wc-action-button-transform: scaleX(-1);\n}"))
    }

    @Test("emitCSS with empty states returns empty string")
    func emitCSSEmptyStates() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Card",
            sourceNode: makeFrame(),
            props: [],
            actions: [],
            bindings: [],
            states: []
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.isEmpty)
    }

    @Test("emitCSS non-root delta produces path-qualified variable name")
    func emitCSSNonRootDelta() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                children: [
                    makeFrame(
                        id: "bg1",
                        name: "Background",
                        fills: .single(.shorthand("#007AFF"))
                    ),
                ]
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: "Background", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let css = StateEmitter.emitCSS(for: [component])
        #expect(css.contains("--wc-action-button-background-bg"))
    }
}
