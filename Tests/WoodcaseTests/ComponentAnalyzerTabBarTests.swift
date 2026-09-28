//
//  ComponentAnalyzerTabBarTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

struct ComponentAnalyzerTabBarTests {
    // MARK: - Helpers

    private func makeFrame(
        id: String = "f1",
        name: String? = nil,
        reusable: Bool? = nil,
        metadata: PenMetadata? = nil,
        fills: PenFills? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, reusable: reusable, metadata: metadata),
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

    // MARK: - ComponentRole

    @Test("tabBar is a valid ComponentRole")
    func tabBarRole() {
        #expect(ComponentRole(rawValue: "tabBar") == .tabBar)
    }

    @Test("tabBar has empty knownStates")
    func tabBarKnownStates() {
        #expect(ComponentRole.tabBar.knownStates.isEmpty)
    }

    // MARK: - RoleStateMapping

    @Test("tabBar trigger always returns nil")
    func tabBarTriggerNil() {
        #expect(RoleStateMapping.trigger(for: .tabBar, state: "home") == nil)
        #expect(RoleStateMapping.trigger(for: .tabBar, state: "anything") == nil)
    }

    @Test("tabBar smart defaults are empty")
    func tabBarSmartDefaults() {
        #expect(RoleStateMapping.smartDefaults(for: .tabBar).isEmpty)
    }

    // MARK: - TabBar Variant Discovery (non-reusable variants)

    @Test("TabBar with non-reusable variants produces 1 component")
    func tabBarMergesNonReusableVariants() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "tab-base",
                name: "Nav",
                reusable: true,
                metadata: ["_role": .string("tabBar")],
                children: [makeText(id: "t1", name: "Home")]
            ),
            makeFrame(
                id: "tab-home",
                name: "Nav:home",
                children: [makeText(id: "t2", name: "Home", content: "Home Active")]
            ),
            makeFrame(
                id: "tab-log",
                name: "Nav:log",
                children: [makeText(id: "t3", name: "Log", content: "Log Active")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let navs = components.filter { $0.name == "Nav" }
        #expect(navs.count == 1)
    }

    // MARK: - TabBar Variant Discovery (reusable variants)

    @Test("TabBar with reusable variants also merges into 1 component")
    func tabBarMergesReusableVariants() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "tab-base",
                name: "Nav",
                reusable: true,
                metadata: ["_role": .string("tabBar")],
                children: [makeText(id: "t1", name: "Home")]
            ),
            makeFrame(
                id: "tab-home",
                name: "Nav:home",
                reusable: true,
                children: [makeText(id: "t2", name: "Home", content: "Home Active")]
            ),
            makeFrame(
                id: "tab-log",
                name: "Nav:log",
                reusable: true,
                children: [makeText(id: "t3", name: "Log", content: "Log Active")]
            ),
            makeFrame(
                id: "tab-ratings",
                name: "Nav:ratings",
                reusable: true,
                children: [makeText(id: "t4", name: "Ratings", content: "Ratings Active")]
            ),
            makeFrame(
                id: "tab-wishlist",
                name: "Nav:wishlist",
                reusable: true,
                children: [makeText(id: "t5", name: "Wishlist", content: "Wishlist Active")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let navs = components.filter { $0.name == "Nav" }
        #expect(navs.count == 1)
    }

    @Test("TabBar has structural states with correct names")
    func tabBarStructuralStates() throws {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "tab-base",
                name: "Nav",
                reusable: true,
                metadata: ["_role": .string("tabBar")],
                children: [makeText(id: "t1", name: "Default")]
            ),
            makeFrame(
                id: "tab-home",
                name: "Nav:home",
                reusable: true,
                children: [makeText(id: "t2", name: "Home")]
            ),
            makeFrame(
                id: "tab-log",
                name: "Nav:log",
                children: [makeText(id: "t3", name: "Log")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let nav = try #require(components.first { $0.name == "Nav" })

        let stateNames = Set(nav.states.map(\.name))
        #expect(stateNames == ["home", "log"])
        for state in nav.states {
            #expect(state.isStructural)
        }
    }

    @Test("TabBar variantIDs maps state name to variant node ID")
    func tabBarVariantIDs() throws {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "tab-base",
                name: "Nav",
                reusable: true,
                metadata: ["_role": .string("tabBar")],
                children: [makeText(id: "t1", name: "Default")]
            ),
            makeFrame(
                id: "tab-home",
                name: "Nav:home",
                reusable: true,
                children: [makeText(id: "t2", name: "Home")]
            ),
            makeFrame(
                id: "tab-log",
                name: "Nav:log",
                children: [makeText(id: "t3", name: "Log")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let nav = try #require(components.first { $0.name == "Nav" })

        #expect(nav.variantIDs["home"] == "tab-home")
        #expect(nav.variantIDs["log"] == "tab-log")
    }

    @Test("Non-tabBar reusable variants are still skipped")
    func nonTabBarReusableStillSkipped() {
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

        // Both should be separate components — reusable variant still skipped for button role
        #expect(components.count == 2)

        let button = components.first { $0.name == "Button" }
        let hoverFromSibling = button?.states.first { $0.name == "hover" && $0.source == .designerOverride }
        #expect(hoverFromSibling == nil)
    }

    @Test("TabBar states have no smart defaults")
    func tabBarNoSmartDefaults() {
        let doc = PenDocument(version: "2.9", children: [
            makeFrame(
                id: "tab-base",
                name: "Nav",
                reusable: true,
                metadata: ["_role": .string("tabBar")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let nav = components.first { $0.name == "Nav" }

        #expect(nav?.states.isEmpty == true)
    }
}
