//
//  RoleStateMappingTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

struct RoleStateMappingTests {
    // MARK: - Trigger Resolution

    @Test("Button triggers map correctly")
    func buttonTriggers() {
        #expect(RoleStateMapping.trigger(for: .button, state: "hover") == .hover)
        #expect(RoleStateMapping.trigger(for: .button, state: "pressed") == .pressed)
        #expect(RoleStateMapping.trigger(for: .button, state: "disabled") == .disabled)
        #expect(RoleStateMapping.trigger(for: .button, state: "focused") == .focused)
    }

    @Test("Link triggers map correctly")
    func linkTriggers() {
        #expect(RoleStateMapping.trigger(for: .link, state: "hover") == .hover)
        #expect(RoleStateMapping.trigger(for: .link, state: "active") == .pressed)
        #expect(RoleStateMapping.trigger(for: .link, state: "focused") == .focused)
    }

    @Test("Toggle triggers map correctly")
    func toggleTriggers() {
        #expect(RoleStateMapping.trigger(for: .toggle, state: "on") == .attribute(name: "enabled", value: "true"))
        #expect(RoleStateMapping.trigger(for: .toggle, state: "disabled") == .disabled)
        #expect(RoleStateMapping.trigger(for: .toggle, state: "focused") == .focused)
    }

    @Test("TextInput triggers map correctly")
    func textInputTriggers() {
        #expect(RoleStateMapping.trigger(for: .textInput, state: "focused") == .focused)
        #expect(RoleStateMapping.trigger(for: .textInput, state: "filled") == .attribute(name: "filled", value: "true"))
        #expect(RoleStateMapping.trigger(for: .textInput, state: "disabled") == .disabled)
    }

    @Test("Select triggers map correctly")
    func selectTriggers() {
        #expect(RoleStateMapping.trigger(for: .select, state: "focused") == .focused)
        #expect(RoleStateMapping.trigger(for: .select, state: "open") == .attribute(name: "open", value: "true"))
        #expect(RoleStateMapping.trigger(for: .select, state: "disabled") == .disabled)
    }

    @Test("Unknown state returns nil")
    func unknownStateReturnsNil() {
        #expect(RoleStateMapping.trigger(for: .button, state: "loading") == nil)
        #expect(RoleStateMapping.trigger(for: .link, state: "pressed") == nil)
    }

    // MARK: - Smart Defaults

    @Test("Button smart defaults return 4 states")
    func buttonSmartDefaults() {
        let defaults = RoleStateMapping.smartDefaults(for: .button)
        #expect(defaults.count == 4)
        let names = defaults.map(\.name)
        #expect(names.contains("hover"))
        #expect(names.contains("pressed"))
        #expect(names.contains("disabled"))
        #expect(names.contains("focused"))
    }

    @Test("Toggle smart defaults return 3 states")
    func toggleSmartDefaults() {
        let defaults = RoleStateMapping.smartDefaults(for: .toggle)
        #expect(defaults.count == 3)
    }

    @Test("Smart default states all have source .smartDefault")
    func smartDefaultSource() {
        for role in [ComponentRole.button, .link, .toggle, .textInput, .select] {
            let defaults = RoleStateMapping.smartDefaults(for: role)
            for state in defaults {
                #expect(state.source == .smartDefault, "State \(state.name) for \(role) should be smartDefault")
            }
        }
    }

    @Test("Smart default states are not structural")
    func smartDefaultsNotStructural() {
        for role in [ComponentRole.button, .link, .toggle, .textInput, .select] {
            let defaults = RoleStateMapping.smartDefaults(for: role)
            for state in defaults {
                #expect(!state.isStructural, "State \(state.name) for \(role) should not be structural")
            }
        }
    }
}
