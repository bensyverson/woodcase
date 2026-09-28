//
//  RoleStateMapping.swift
//  Woodcase
//

/// Maps component roles to their state triggers and provides smart default state definitions.
public enum RoleStateMapping {
    /// Returns the trigger for a known state name on a given role, or nil if unknown.
    public static func trigger(for role: ComponentRole, state: String) -> StateTrigger? {
        switch (role, state) {
        // Button
        case (.button, "hover"): .hover
        case (.button, "pressed"): .pressed
        case (.button, "disabled"): .disabled
        case (.button, "focused"): .focused
        // Link
        case (.link, "hover"): .hover
        case (.link, "active"): .pressed
        case (.link, "focused"): .focused
        // Toggle
        case (.toggle, "on"): .attribute(name: "enabled", value: "true")
        case (.toggle, "disabled"): .disabled
        case (.toggle, "focused"): .focused
        // TextInput
        case (.textInput, "focused"): .focused
        case (.textInput, "filled"): .attribute(name: "filled", value: "true")
        case (.textInput, "disabled"): .disabled
        // Select
        case (.select, "focused"): .focused
        case (.select, "open"): .attribute(name: "open", value: "true")
        case (.select, "disabled"): .disabled
        default: nil
        }
    }

    /// Returns smart default state definitions for a role.
    ///
    /// Each carries its trigger's ``smartEffects(for:)`` and no property deltas: the
    /// effects apply to the whole component, so they rarely conflict with its own styles.
    public static func smartDefaults(for role: ComponentRole) -> [StateDefinition] {
        role.knownStates.compactMap { stateName in
            guard let trigger = trigger(for: role, state: stateName) else { return nil }
            return StateDefinition(
                name: stateName,
                trigger: trigger,
                source: .smartDefault,
                isStructural: false,
                deltas: [],
                effects: smartEffects(for: trigger),
                variantNode: nil
            )
        }
    }

    /// The effects a smart-default state applies for a trigger — the one definition every
    /// emitter spells.
    ///
    /// An interaction gets a light touch: a hovered component dims, a pressed one shrinks,
    /// a focused one gets a ring, a disabled one fades and ignores the pointer. An attribute
    /// state (a toggle's `on`, a text input's `filled`, a select's `open`) has no neutral
    /// look, so the designer must draw it.
    public static func smartEffects(for trigger: StateTrigger) -> [StateEffect] {
        switch trigger {
        case .hover: [.dim(brightness: 0.95)]
        case .pressed: [.scale(factor: 0.98)]
        case .focused: [.focusRing(width: 2, offset: 2)]
        case .disabled: [.fade(opacity: 0.5), .ignoresPointer]
        case .attribute: []
        }
    }
}
