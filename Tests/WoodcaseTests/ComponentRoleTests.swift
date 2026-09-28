//
//  ComponentRoleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ComponentRoleTests {
    // MARK: - Parsing

    @Test("Parses known role strings")
    func parsesKnownRoles() {
        #expect(ComponentRole(rawValue: "button") == .button)
        #expect(ComponentRole(rawValue: "link") == .link)
        #expect(ComponentRole(rawValue: "toggle") == .toggle)
        #expect(ComponentRole(rawValue: "textInput") == .textInput)
        #expect(ComponentRole(rawValue: "select") == .select)
    }

    @Test("Unknown strings return nil")
    func unknownStringsReturnNil() {
        #expect(ComponentRole(rawValue: "checkbox") == nil)
        #expect(ComponentRole(rawValue: "slider") == nil)
        #expect(ComponentRole(rawValue: "") == nil)
    }

    // MARK: - Known States

    @Test("Button has expected known states")
    func buttonKnownStates() {
        let states = ComponentRole.button.knownStates
        #expect(states == ["hover", "pressed", "disabled", "focused"])
    }

    @Test("Link has expected known states")
    func linkKnownStates() {
        let states = ComponentRole.link.knownStates
        #expect(states == ["hover", "active", "focused"])
    }

    @Test("Toggle has expected known states")
    func toggleKnownStates() {
        let states = ComponentRole.toggle.knownStates
        #expect(states == ["on", "disabled", "focused"])
    }

    @Test("TextInput has expected known states")
    func textInputKnownStates() {
        let states = ComponentRole.textInput.knownStates
        #expect(states == ["focused", "filled", "disabled"])
    }

    @Test("Select has expected known states")
    func selectKnownStates() {
        let states = ComponentRole.select.knownStates
        #expect(states == ["focused", "open", "disabled"])
    }

    // MARK: - Friendly Conformance

    @Test("ComponentRole is Codable round-trippable")
    func codableRoundTrip() throws {
        let role = ComponentRole.button
        let data = try JSONEncoder().encode(role)
        let decoded = try JSONDecoder().decode(ComponentRole.self, from: data)
        #expect(decoded == role)
    }
}
