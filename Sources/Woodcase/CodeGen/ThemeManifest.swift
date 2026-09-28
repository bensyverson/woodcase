//
//  ThemeManifest.swift
//  Woodcase
//

/// A summary of theming information extracted from a .pen document for code generation.
///
/// Captures theme axes, all variables with their themed values, and nodes that
/// declare theme context overrides.
public struct ThemeManifest: Friendly {
    public init(
        axes: [ThemeAxis],
        variables: [VariableInfo],
        contextNodes: [String]
    ) {
        self.axes = axes
        self.variables = variables
        self.contextNodes = contextNodes
    }

    /// Theme axes (e.g., mode: light/dark, density: default/compact).
    public var axes: [ThemeAxis]

    /// All variables with type and themed status.
    public var variables: [VariableInfo]

    /// Node IDs that have theme context overrides.
    public var contextNodes: [String]
}

/// A single theme axis with its possible values.
public struct ThemeAxis: Friendly {
    public init(name: String, values: [String]) {
        self.name = name
        self.values = values
    }

    /// Axis name (e.g., "mode").
    public var name: String

    /// Possible values (e.g., ["light", "dark"]).
    public var values: [String]
}

/// Information about a single variable for code generation.
public struct VariableInfo: Friendly {
    public init(
        name: String,
        type: PenVariableType,
        isThemed: Bool,
        values: [ThemedVariableValue]
    ) {
        self.name = name
        self.type = type
        self.isThemed = isThemed
        self.values = values
    }

    /// Variable name (e.g., "bg-page").
    public var name: String

    /// Variable type from the .pen format.
    public var type: PenVariableType

    /// Whether this variable has theme-dependent values.
    public var isThemed: Bool

    /// All values with their theme conditions.
    public var values: [ThemedVariableValue]
}

/// A single value for a variable, possibly with theme conditions.
public struct ThemedVariableValue: Friendly {
    public init(
        value: AnyCodable,
        conditions: [String: String]
    ) {
        self.value = value
        self.conditions = conditions
    }

    /// The resolved value.
    public var value: AnyCodable

    /// Theme conditions (e.g., {"mode": "dark"}). Empty for default/unconditional values.
    public var conditions: [String: String]
}
