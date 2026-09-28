//
//  ComponentRole.swift
//  Woodcase
//

/// The interactive role of a component, determining its known states and semantic behavior.
public enum ComponentRole: String, Friendly, CaseIterable {
    case button
    case link
    case toggle
    case textInput
    case select
    case tabBar

    /// The well-known state names for this role.
    public var knownStates: [String] {
        switch self {
        case .button: ["hover", "pressed", "disabled", "focused"]
        case .link: ["hover", "active", "focused"]
        case .toggle: ["on", "disabled", "focused"]
        case .textInput: ["focused", "filled", "disabled"]
        case .select: ["focused", "open", "disabled"]
        case .tabBar: []
        }
    }
}
