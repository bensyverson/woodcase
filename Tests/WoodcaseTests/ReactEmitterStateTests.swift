//
//  ReactEmitterStateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ReactEmitterStateTests {
    // MARK: - Helpers

    private func makeFrame(
        id: String = "f1",
        name: String? = nil,
        reusable: Bool? = nil,
        metadata: PenMetadata? = nil,
        rotation: PenValue<Double>? = nil,
        fills: PenFills? = nil,
        width: PenSizing? = nil,
        height: PenSizing? = nil,
        layout: PenLayoutDirection? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(
                name: name, rotation: rotation, reusable: reusable, metadata: metadata
            ),
            kind: .frame(PenNode.FrameData(
                width: width, height: height, fills: fills, layout: layout, children: children
            ))
        )
    }

    private func makeText(
        id: String = "t1",
        name: String? = nil,
        content: String = "Hello",
        fills: PenFills? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .text(PenNode.TextData(
                content: .literal(content), fills: fills
            ))
        )
    }

    private func emit(_ component: ComponentDefinition) -> String {
        let theme = ThemeManifest(axes: [], variables: [], contextNodes: [])
        let result = ReactEmitter.emit(
            document: PenDocument(version: "2.9", children: []),
            components: [component],
            theme: theme
        )
        return result.files.first { $0.path.starts(with: "components/") }?.content ?? ""
    }

    // MARK: - Step 2: var() substitution and wc-* class

    @Test("Component with button role + hover fill override: root gets wc-* class")
    func rootGetsWcClass() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                fills: .single(.shorthand("#007AFF")),
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
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
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let output = emit(component)
        #expect(output.contains("wc-action-button"))
    }

    @Test("Component with button role + hover fill override: backgroundColor uses var()")
    func backgroundColorUsesVar() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                fills: .single(.shorthand("#007AFF")),
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
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
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let output = emit(component)
        #expect(output.contains("var(--wc-action-button-bg)"))
    }

    @Test("Component with a rotate/flip designer state: root's transform style uses var()")
    func transformStateUsesVar() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
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

        let output = emit(component)
        #expect(output.contains("transform: \"var(--wc-action-button-transform)\""))
    }

    @Test("A free-positioned child with a transform state turns about its x/y, as Pen does")
    func transformStateOnFreeChildPivotsAtAnchor() {
        let target = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Target", x: .literal(35), y: .literal(35)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(50), height: .fixed(50)))
        )
        let component = ComponentDefinition(
            id: "c1",
            name: "TurnedCard",
            sourceNode: makeFrame(
                name: "TurnedCard", width: .fixed(120), height: .fixed(120), layout: PenLayoutDirection.none,
                children: [target]
            ),
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
                        StateDelta(nodePath: "Target", changes: [
                            PropertyChange(transform: DeltaTransform(rotation: 25, flipX: false, flipY: false)),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let output = emit(component)
        #expect(output.contains("transform: \"var(--wc-turned-card-target-transform)\""))
        #expect(output.contains("transformOrigin: \"0 0\""))
    }

    @Test("Component with role but no designer states: no var() substitution")
    func noDesignerStatesNoVar() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                fills: .single(.shorthand("#007AFF")),
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
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

        let output = emit(component)
        #expect(!output.contains("var(--"))
    }

    @Test("Component with no role: output unchanged")
    func noRoleUnchanged() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Card",
            sourceNode: makeFrame(
                name: "Card",
                fills: .single(.shorthand("#FFFFFF")),
                width: .fixed(300),
                height: .fixed(200),
                layout: .vertical
            ),
            props: [],
            actions: [],
            bindings: [],
            states: []
        )

        let output = emit(component)
        #expect(!output.contains("var(--"))
        #expect(!output.contains("wc-"))
        #expect(output.contains("<div"))
    }

    @Test("Non-root child with state-affected property: path-qualified var() name")
    func nonRootChildVar() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal,
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

        let output = emit(component)
        #expect(output.contains("var(--wc-action-button-background-bg)"))
    }

    // MARK: - Step 3: Semantic HTML elements

    @Test("Button role emits <button> tag")
    func buttonRoleEmitsButton() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: []
        )

        let output = emit(component)
        #expect(output.contains("<button"))
        #expect(output.contains("type=\"button\""))
        #expect(output.contains("</button>"))
    }

    @Test("Link role emits <a> tag")
    func linkRoleEmitsAnchor() {
        let component = ComponentDefinition(
            id: "c1",
            name: "NavLink",
            sourceNode: makeFrame(
                name: "NavLink",
                width: .fixed(100),
                height: .fixed(40),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .link,
            states: []
        )

        let output = emit(component)
        #expect(output.contains("<a"))
        #expect(output.contains("</a>"))
    }

    @Test("Toggle role emits checked prop, aria-checked, and data-off attribute")
    func toggleRoleEmitsChecked() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Toggle",
            sourceNode: makeFrame(
                name: "Toggle",
                fills: .single(.shorthand("#007AFF")),
                width: .fixed(44),
                height: .fixed(24),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .toggle,
            states: [
                StateDefinition(
                    name: "off",
                    trigger: .attribute(name: "off", value: "true"),
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#999")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let output = emit(component)
        #expect(output.contains("checked?: boolean"))
        #expect(output.contains("checked = true"))
        #expect(output.contains("role=\"switch\""))
        #expect(output.contains("aria-checked={checked}"))
        #expect(output.contains("data-off={!checked ? \"true\" : undefined}"))
    }

    @Test("No role emits <div>")
    func noRoleEmitsDiv() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Card",
            sourceNode: makeFrame(
                name: "Card",
                width: .fixed(300),
                height: .fixed(200),
                layout: .vertical
            ),
            props: [],
            actions: [],
            bindings: [],
            states: []
        )

        let output = emit(component)
        #expect(output.contains("<div"))
        #expect(!output.contains("<button"))
        #expect(!output.contains("<a"))
    }

    // MARK: - Step 4: Interface props + data attributes

    @Test("Button interface includes disabled prop")
    func buttonInterfaceDisabled() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: []
        )

        let output = emit(component)
        #expect(output.contains("disabled?: boolean;"))
    }

    @Test("Link interface includes href prop but no disabled")
    func linkInterfaceHref() {
        let component = ComponentDefinition(
            id: "c1",
            name: "NavLink",
            sourceNode: makeFrame(
                name: "NavLink",
                width: .fixed(100),
                height: .fixed(40),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .link,
            states: []
        )

        let output = emit(component)
        #expect(output.contains("href?: string;"))
        #expect(!output.contains("disabled?: boolean;"))
    }

    @Test("Button root has disabled={disabled} attribute")
    func buttonDisabledAttr() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: []
        )

        let output = emit(component)
        #expect(output.contains("disabled={disabled}"))
    }

    @Test("Link root has href={href} attribute")
    func linkHrefAttr() {
        let component = ComponentDefinition(
            id: "c1",
            name: "NavLink",
            sourceNode: makeFrame(
                name: "NavLink",
                width: .fixed(100),
                height: .fixed(40),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .link,
            states: []
        )

        let output = emit(component)
        #expect(output.contains("href={href}"))
    }

    // MARK: - Step 5: Structural state emission

    @Test("Component with one structural state emits default + variant render functions")
    func structuralStateRendersVariant() {
        let variantNode = makeFrame(
            name: "ActionButton",
            fills: .single(.shorthand("#FF0000")),
            width: .fixed(200),
            height: .fixed(48),
            layout: .horizontal,
            children: [
                makeText(id: "t-loading", name: "Label", content: "Loading..."),
            ]
        )

        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                fills: .single(.shorthand("#007AFF")),
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal,
                children: [
                    makeText(id: "t1", name: "Label", content: "Submit"),
                ]
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "loading",
                    trigger: .pressed,
                    source: .designerOverride,
                    isStructural: true,
                    deltas: [],
                    variantNode: variantNode
                ),
            ]
        )

        let output = emit(component)
        #expect(output.contains("function ActionButtonDefault("))
        #expect(output.contains("function ActionButtonLoading("))
        #expect(output.contains("export function ActionButton("))
    }

    @Test("Structural state prop appears in interface")
    func structuralStatePropInInterface() {
        let variantNode = makeFrame(
            name: "ActionButton",
            width: .fixed(200),
            height: .fixed(48),
            layout: .horizontal
        )

        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "loading",
                    trigger: .pressed,
                    source: .designerOverride,
                    isStructural: true,
                    deltas: [],
                    variantNode: variantNode
                ),
            ]
        )

        let output = emit(component)
        #expect(output.contains("loading?: boolean;"))
    }

    @Test("Component without structural states uses simple export function")
    func noStructuralStatesSimpleFunction() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
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

        let output = emit(component)
        #expect(output.contains("export function ActionButton("))
        #expect(!output.contains("function ActionButtonDefault("))
    }

    // MARK: - Step 6: TabBar N-way dispatch

    private func makeTabBarComponent() -> ComponentDefinition {
        let homeVariant = makeFrame(
            name: "Nav",
            width: .fixed(400),
            height: .fixed(60),
            layout: .horizontal,
            children: [makeText(id: "th", name: "Home", content: "Home Active")]
        )
        let logVariant = makeFrame(
            name: "Nav",
            width: .fixed(400),
            height: .fixed(60),
            layout: .horizontal,
            children: [makeText(id: "tl", name: "Log", content: "Log Active")]
        )

        return ComponentDefinition(
            id: "c1",
            name: "Nav",
            sourceNode: makeFrame(
                name: "Nav",
                width: .fixed(400),
                height: .fixed(60),
                layout: .horizontal,
                children: [makeText(id: "td", name: "Default", content: "Default")]
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .tabBar,
            states: [
                StateDefinition(
                    name: "home",
                    trigger: .attribute(name: "home", value: "true"),
                    source: .designerOverride,
                    isStructural: true,
                    deltas: [],
                    variantNode: homeVariant
                ),
                StateDefinition(
                    name: "log",
                    trigger: .attribute(name: "log", value: "true"),
                    source: .designerOverride,
                    isStructural: true,
                    deltas: [],
                    variantNode: logVariant
                ),
            ],
            variantIDs: ["home": "v-home", "log": "v-log"]
        )
    }

    @Test("TabBar emits selected string union prop, not boolean state props")
    func tabBarSelectedProp() {
        let output = emit(makeTabBarComponent())
        #expect(output.contains("selected?: \"home\" | \"log\""))
        #expect(!output.contains("home?: boolean"))
        #expect(!output.contains("log?: boolean"))
    }

    @Test("TabBar wrapper uses selected === dispatch")
    func tabBarSelectedDispatch() {
        let output = emit(makeTabBarComponent())
        #expect(output.contains("selected === \"home\""))
        #expect(output.contains("selected === \"log\""))
        #expect(output.contains("<NavDefault"))
    }

    @Test("TabBar wrapper destructures selected")
    func tabBarDestructuresSelected() {
        let output = emit(makeTabBarComponent())
        #expect(output.contains("  selected,"))
    }

    @Test("TabBar root emits <nav role=\"tablist\">")
    func tabBarNavRole() {
        let output = emit(makeTabBarComponent())
        #expect(output.contains("<nav"))
        #expect(output.contains("role=\"tablist\""))
    }

    @Test("TabBar default fallback renders NavDefault")
    func tabBarDefaultFallback() {
        let output = emit(makeTabBarComponent())
        #expect(output.contains("function NavDefault("))
        #expect(output.contains("<NavDefault {...props} />"))
    }

    // MARK: - Step 7: TabBar ref resolution

    @Test("Ref to tabBar variant ID emits <Nav selected=\"home\" />")
    func tabBarVariantRefResolution() throws {
        let tabBar = makeTabBarComponent()

        // Create a page-like component that refs the variant ID
        let page = ComponentDefinition(
            id: "page1",
            name: "SettingsPage",
            sourceNode: makeFrame(
                name: "SettingsPage",
                width: .fixed(400),
                height: .fixed(800),
                layout: .vertical,
                children: [
                    PenNode(
                        id: "ref1",
                        common: PenNodeCommon(name: "Tab Bar Ref"),
                        kind: .ref(PenNode.RefData(ref: "v-home"))
                    ),
                ]
            ),
            props: [],
            actions: [],
            bindings: []
        )

        let theme = ThemeManifest(axes: [], variables: [], contextNodes: [])
        let result = ReactEmitter.emit(
            document: PenDocument(version: "2.9", children: []),
            components: [tabBar, page],
            theme: theme
        )

        let pageFile = try #require(result.files.first { $0.path == "components/SettingsPage.tsx" })
        #expect(pageFile.content.contains("<Nav selected=\"home\" />"))
        #expect(pageFile.content.contains("import { Nav }"))
    }
}
