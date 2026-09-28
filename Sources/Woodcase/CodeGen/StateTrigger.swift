//
//  StateTrigger.swift
//  Woodcase
//

/// What puts a component in a state at runtime, named by the state rather than by any
/// target's mechanism for it.
///
/// Each emitter maps a trigger to its own: React to a CSS selector (``StateEmitter``),
/// SwiftUI to a button style's `isPressed`, `.onHover`, `isEnabled` or `@FocusState`.
public enum StateTrigger: Friendly {
    /// The pointer is over the component.
    case hover

    /// The component is being pressed (a link's `active` state is this too).
    case pressed

    /// The component is disabled.
    case disabled

    /// The component, or the control inside it, has keyboard focus.
    case focused

    /// The caller sets a named attribute to a value: a toggle's `enabled`, a select's
    /// `open`, or any state a role does not name.
    case attribute(name: String, value: String)
}
