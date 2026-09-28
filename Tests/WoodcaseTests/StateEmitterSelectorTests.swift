//
//  StateEmitterSelectorTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

/// Pins the CSS selector the React emitter writes for each neutral state trigger.
struct StateEmitterSelectorTests {
    private static let cases: [(StateTrigger, ComponentRole?, String)] = [
        (.hover, .button, ".wc-x:hover"),
        (.pressed, .button, ".wc-x:active"),
        (.pressed, .link, ".wc-x:active"),
        (.disabled, .toggle, ".wc-x:disabled"),
        (.focused, .button, ".wc-x:focus-visible"),
        (.focused, .link, ".wc-x:focus-visible"),
        (.focused, .toggle, ".wc-x:focus-visible"),
        (.focused, nil, ".wc-x:focus-visible"),
        (.attribute(name: "enabled", value: "true"), .toggle, ".wc-x[data-enabled=\"true\"]"),
        (.attribute(name: "home", value: "true"), nil, ".wc-x[data-home=\"true\"]"),
    ]

    @Test("Each state maps to the selector React has always written", arguments: cases)
    func selector(trigger: StateTrigger, role: ComponentRole?, expected: String) {
        #expect(StateEmitter.selector(for: trigger, role: role, className: "wc-x") == expected)
    }

    @Test(
        "Focus on a text input or select is focus-within: the focus lands on the inner control",
        arguments: [ComponentRole.textInput, .select]
    )
    func focusWithin(role: ComponentRole) {
        #expect(StateEmitter.selector(for: .focused, role: role, className: "wc-x") == ".wc-x:focus-within")
    }
}
