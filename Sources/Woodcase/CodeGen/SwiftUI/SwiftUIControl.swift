//
//  SwiftUIControl.swift
//  Woodcase
//

/// A component with a role or states, as the SwiftUI emitter writes it: the SwiftUI control
/// its role becomes, the faces it draws for the states the designer drew, and the smart
/// defaults it spells as modifiers for the rest.
///
/// Target-neutral decisions stay in the analysis — which states a role knows, what
/// triggers each, what a smart default does (``RoleStateMapping``); this type decides only
/// how SwiftUI reads a trigger and which face wins when several states hold at once.
struct SwiftUIControl: Friendly {
    /// The SwiftUI control a role becomes.
    enum Kind: String, Friendly {
        /// `button` and `link`: a `Button` with an action, drawn by a `ButtonStyle`.
        case button
        /// `toggle`: a `Toggle` bound to `isOn`, drawn by a `ToggleStyle`.
        case toggle
        /// `textInput`: the component with its first text drawn as a `TextField`.
        case textField
        /// `select`: a `Menu` holding an inline `Picker`, its label drawn by a `ButtonStyle`.
        case picker
        /// `tabBar`: drawn for its `selected` tab.
        case tabBar
        /// No role: drawn for the `variant` the caller sets.
        case plain

        /// The kind a component of `role` becomes.
        init(_ role: ComponentRole?) {
            switch role {
            case .button, .link: self = .button
            case .toggle: self = .toggle
            case .textInput: self = .textField
            case .select: self = .picker
            case .tabBar: self = .tabBar
            case nil: self = .plain
            }
        }

        /// Whether the states are drawn by a style's `makeBody`, which reads the
        /// component's members through its `view`.
        var isStyled: Bool {
            self == .button || self == .toggle || self == .picker
        }
    }

    /// A state the designer drew a frame for, and the private property that draws it.
    struct Face: Friendly {
        /// The state.
        var state: StateDefinition
        /// The designer's frame for it.
        var node: PenNode
        /// The property's name: `pressedFace`.
        var property: String
    }

    /// The control the component becomes.
    var kind: Kind

    /// The states drawn from the designer's frames, the first whose condition holds winning:
    /// disabled, then pressed, hovered and focused, then the attribute states in the
    /// analyzer's order.
    var faces: [Face]

    /// The states whose effects are applied as modifiers: the smart defaults, and the
    /// designer's states this control draws as a smart default instead (``skipped``).
    var effects: [StateDefinition]

    /// The designer's states drawn as their smart default, because drawing their frame
    /// would take the focus from the text field (a text input's `focused` and `filled`).
    var skipped: [StateDefinition]

    /// The cases of the enum the caller picks a face by — `Tab` for a tab bar, `Variant`
    /// otherwise: the attribute states with a face that no SwiftUI control reports.
    var cases: [String]

    /// The control `definition` becomes, or `nil` when it has neither a role nor states.
    init?(_ definition: ComponentDefinition) {
        guard definition.role != nil || !definition.states.isEmpty else { return nil }
        kind = Kind(definition.role)
        var faces: [Face] = []
        var effects: [StateDefinition] = []
        var skipped: [StateDefinition] = []
        for state in definition.states {
            if state.source == .smartDefault {
                effects.append(state)
            } else if let node = state.variantNode {
                if Self.dropsFocus(state, kind: kind) {
                    skipped.append(state)
                    var fallback = state
                    fallback.effects = RoleStateMapping.smartEffects(for: state.trigger)
                    effects.append(fallback)
                } else {
                    faces.append(Face(state: state, node: node, property: SwiftUIProp.identifier(state.name) + "Face"))
                }
            }
        }
        self.faces = faces.enumerated()
            .sorted { (Self.rank($0.element.state.trigger), $0.offset) < (Self.rank($1.element.state.trigger), $1.offset) }
            .map(\.element)
        self.effects = effects.filter { !$0.effects.isEmpty }
        self.skipped = skipped
        let kind = kind
        cases = faces.filter { Self.isCallerSet($0.state, kind: kind) }.map { SwiftUIProp.identifier($0.state.name) }
    }

    /// The enum a caller picks a face by: `Tab` for a tab bar, `Variant` otherwise.
    var enumName: String {
        kind == .tabBar ? "Tab" : "Variant"
    }

    /// The property that holds the caller's pick: `selected` for a tab bar, `variant` otherwise.
    var enumProperty: String {
        kind == .tabBar ? "selected" : "variant"
    }

    /// Whether a reader must supply the interaction state: some face or effect depends on it.
    var readsState: Bool {
        !effects.isEmpty || faces.contains { !Self.isAttribute($0.state.trigger) }
    }

    /// The Swift condition that holds while `state` does, its members read through
    /// `member` (`view.variant` in a style, `variant` in the body).
    func condition(for state: StateDefinition, member: (String) -> String) -> String {
        switch state.trigger {
        case .hover: return "state.contains(.hovered)"
        case .pressed: return "state.contains(.pressed)"
        case .disabled: return "state.contains(.disabled)"
        case .focused: return "state.contains(.focused)"
        case .attribute:
            if kind == .toggle, state.name == "on" { return "configuration.isOn" }
            if kind == .toggle, state.name == "off" { return "!configuration.isOn" }
            if kind == .textField, state.name == "filled" { return "!\(member("text")).isEmpty" }
            return "\(member(enumProperty)) == .\(SwiftUIProp.identifier(state.name))"
        }
    }

    /// Whether the caller sets `state` through the enum, because no SwiftUI control
    /// reports it.
    private static func isCallerSet(_ state: StateDefinition, kind: Kind) -> Bool {
        guard isAttribute(state.trigger) else { return false }
        switch kind {
        case .toggle: return state.name != "on" && state.name != "off"
        case .textField: return state.name != "filled"
        default: return true
        }
    }

    /// Whether drawing `state`'s frame would drop a text field's focus: a branch swap
    /// makes a new `TextField`, so a state that holds while the field is being typed into
    /// cannot swap it.
    private static func dropsFocus(_ state: StateDefinition, kind: Kind) -> Bool {
        guard kind == .textField else { return false }
        if case .focused = state.trigger { return true }
        return state.name == "filled"
    }

    /// Whether `trigger` is an attribute the caller sets, rather than an interaction.
    private static func isAttribute(_ trigger: StateTrigger) -> Bool {
        if case .attribute = trigger { true } else { false }
    }

    /// The order faces are tried in: disabled wins over a press, a press over a hover, a
    /// hover over focus, and every interaction over an attribute.
    private static func rank(_ trigger: StateTrigger) -> Int {
        switch trigger {
        case .disabled: 0
        case .pressed: 1
        case .hover: 2
        case .focused: 3
        case .attribute: 4
        }
    }
}
