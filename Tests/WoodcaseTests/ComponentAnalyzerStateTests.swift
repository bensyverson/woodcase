//
//  ComponentAnalyzerStateTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

struct ComponentAnalyzerStateTests {
    // MARK: - Helpers

    private func makeFrame(
        id: String = "f1",
        name: String? = nil,
        reusable: Bool? = nil,
        metadata: PenMetadata? = nil,
        fills: PenFills? = nil,
        opacity: PenValue<Double>? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, opacity: opacity, reusable: reusable, metadata: metadata),
            kind: .frame(PenNode.FrameData(fills: fills, children: children))
        )
    }

    private func makeText(
        id: String = "t1",
        name: String? = nil,
        content: String = "Hello"
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .text(PenNode.TextData(content: .literal(content)))
        )
    }

    // MARK: - Variant Discovery via Naming Convention

    @Test("Component with Button:hover sibling discovers hover state")
    func hoverSiblingDiscovered() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(
                id: "btn-hover",
                name: "Button:hover",
                fills: .single(.shorthand("#0051D5"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        #expect(button != nil)
        let hoverState = button?.states.first { $0.name == "hover" }
        #expect(hoverState != nil)
        #expect(hoverState?.source == .designerOverride)
    }

    @Test("Component with multiple variants discovers all")
    func multipleVariantsDiscovered() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(
                id: "btn-hover",
                name: "Button:hover",
                fills: .single(.shorthand("#0051D5"))
            ),
            makeFrame(
                id: "btn-disabled",
                name: "Button:disabled",
                fills: .single(.shorthand("#CCCCCC"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        let stateNames = Set(button?.states.map(\.name) ?? [])
        #expect(stateNames.contains("hover"))
        #expect(stateNames.contains("disabled"))
    }

    @Test("Reusable Button:hover sibling is treated as its own component, not a variant")
    func reusableVariantNotTreatedAsState() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(
                id: "btn-hover",
                name: "Button:hover",
                reusable: true,
                fills: .single(.shorthand("#0051D5"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        // Both should be separate components
        #expect(components.count == 2)

        // The original button should NOT have hover as a designer override from the sibling
        let button = components.first { $0.name == "Button" }
        let hoverFromSibling = button?.states.first { $0.name == "hover" && $0.source == .designerOverride }
        #expect(hoverFromSibling == nil)
    }

    // MARK: - _states Metadata

    @Test("_states metadata discovers variant by node ID")
    func statesMetadataDiscovery() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: [
                    "_role": .string("button"),
                    "_states": .dictionary([
                        "hover": .string("hover-variant-id"),
                    ]),
                ],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(
                id: "hover-variant-id",
                name: "Hidden Hover Frame",
                fills: .single(.shorthand("#0051D5"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        let hoverState = button?.states.first { $0.name == "hover" }
        #expect(hoverState != nil)
        #expect(hoverState?.source == .designerOverride)
    }

    @Test("_states takes precedence over naming convention for same state")
    func statesMetadataPrecedence() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: [
                    "_role": .string("button"),
                    "_states": .dictionary([
                        "hover": .string("explicit-hover"),
                    ]),
                ],
                fills: .single(.shorthand("#007AFF"))
            ),
            // _states hover variant
            makeFrame(
                id: "explicit-hover",
                name: "My Hover",
                fills: .single(.shorthand("#FF0000"))
            ),
            // Naming convention hover variant (should be ignored)
            makeFrame(
                id: "naming-hover",
                name: "Button:hover",
                fills: .single(.shorthand("#00FF00"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        // Should have exactly one hover state, from _states metadata
        let hoverStates = button?.states.filter { $0.name == "hover" } ?? []
        #expect(hoverStates.count == 1)
    }

    // MARK: - Smart Defaults

    @Test("Component with role and no variants gets smart defaults")
    func smartDefaultsApplied() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                fills: .single(.shorthand("#007AFF"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        // Button role has 4 smart defaults: hover, pressed, disabled, focused
        #expect(button?.states.count == 4)
        let sources = Set(button?.states.map(\.source) ?? [])
        #expect(sources == [.smartDefault])
    }

    @Test("Smart default hover is suppressed when designer provides hover")
    func smartDefaultSuppressed() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(
                id: "btn-hover",
                name: "Button:hover",
                fills: .single(.shorthand("#0051D5"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        // Should have 4 states total: 1 designer override (hover) + 3 smart defaults
        #expect(button?.states.count == 4)

        let hover = button?.states.first { $0.name == "hover" }
        #expect(hover?.source == .designerOverride)

        // The other 3 should be smart defaults
        let defaults = button?.states.filter { $0.source == .smartDefault } ?? []
        #expect(defaults.count == 3)
    }

    // MARK: - No Role

    @Test("Component with no role and no variants has empty states")
    func noRoleNoVariants() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "card",
                name: "Card",
                reusable: true,
                fills: .single(.shorthand("#FFFFFF"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let card = components.first { $0.name == "Card" }

        #expect(card?.states.isEmpty == true)
    }

    // MARK: - Role Parsing

    @Test("Role parsed from _role metadata")
    func roleParsed() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        #expect(button?.role == .button)
    }

    @Test("Unknown role string results in nil role")
    func unknownRole() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "comp",
                name: "Widget",
                reusable: true,
                metadata: ["_role": .string("slider")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let widget = components.first { $0.name == "Widget" }

        #expect(widget?.role == nil)
    }

    @Test("Component without _role has nil role")
    func noRoleMetadata() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "card",
                name: "Card",
                reusable: true
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components.first?.role == nil)
    }

    // MARK: - Structural Detection

    @Test("Structural variant with added child is flagged")
    func structuralVariant() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                children: [
                    makeText(id: "label", name: "Label", content: "Submit"),
                ]
            ),
            makeFrame(
                id: "btn-loading",
                name: "Button:pressed",
                children: [
                    makeText(id: "label2", name: "Label", content: "Submit"),
                    makeFrame(id: "spinner", name: "Spinner"),
                ]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        let pressed = button?.states.first { $0.name == "pressed" }
        #expect(pressed?.isStructural == true)
    }

    // MARK: - Case-Insensitive State Matching

    @Test("State name matching is case-insensitive")
    func caseInsensitiveMatching() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn",
                name: "Button",
                reusable: true,
                metadata: ["_role": .string("button")],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(
                id: "btn-hover",
                name: "Button:Hover",
                fills: .single(.shorthand("#0051D5"))
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let button = components.first { $0.name == "Button" }

        let hoverState = button?.states.first { $0.name == "hover" }
        #expect(hoverState != nil)
        #expect(hoverState?.source == .designerOverride)
    }

    // MARK: - Variant Nodes

    @Test("A designer state keeps its variant's tree even when it is no structural change")
    func designerStateKeepsVariantNode() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "btn", name: "Button", reusable: true,
                metadata: ["_role": .string("button"), "_states": .dictionary(["loading": .string("btn-load")])],
                fills: .single(.shorthand("#007AFF"))
            ),
            makeFrame(id: "btn-pressed", name: "Button:pressed", fills: .single(.shorthand("#0051D5"))),
            makeFrame(id: "btn-load", name: "Loading", fills: .single(.shorthand("#999999"))),
        ])

        let button = ComponentAnalyzer.analyze(doc).first { $0.name == "Button" }
        let pressed = button?.states.first { $0.name == "pressed" }
        let loading = button?.states.first { $0.name == "loading" }
        #expect(pressed?.isStructural == false)
        #expect(pressed?.variantNode?.id == "btn-pressed")
        #expect(loading?.isStructural == false)
        #expect(loading?.variantNode?.id == "btn-load")
    }
}
