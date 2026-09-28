//
//  StateDefinition.swift
//  Woodcase
//

/// A single interactive state for a component, with its trigger, source, property deltas and
/// whole-component effects.
public struct StateDefinition: Friendly {
    /// Creates a state; `effects` defaults to none, as a designer's state carries.
    public init(
        name: String,
        trigger: StateTrigger,
        source: StateSource,
        isStructural: Bool,
        deltas: [StateDelta],
        effects: [StateEffect] = [],
        variantNode: PenNode?
    ) {
        self.name = name
        self.trigger = trigger
        self.source = source
        self.isStructural = isStructural
        self.deltas = deltas
        self.effects = effects
        self.variantNode = variantNode
    }

    /// The state name (e.g., "hover", "pressed", "on").
    public var name: String

    /// What puts the component in this state: an interaction, or an attribute the caller sets.
    public var trigger: StateTrigger

    /// Where this state definition came from.
    public var source: StateSource

    /// Whether the variant has structural changes (added/removed/reordered children).
    public var isStructural: Bool

    /// The pen-level property changes for this state.
    public var deltas: [StateDelta]

    /// The whole-component effects this state applies, such as a smart default's dim on
    /// hover. A designer's state draws its change instead, and carries none.
    public var effects: [StateEffect]

    /// The designer's frame for this state, whole, so an emitter can draw it rather than
    /// apply ``deltas``: React re-emits it for a structural state, SwiftUI for every
    /// designer's state. `nil` for a smart default, which has no frame.
    public var variantNode: PenNode?
}

/// Where a state definition originated.
public enum StateSource: String, Friendly {
    /// Auto-generated from the component's role.
    case smartDefault

    /// Explicitly designed via a `{Name}:{state}` sibling or `_states` metadata.
    case designerOverride

    /// Driven by a bound prop value.
    case binding
}
