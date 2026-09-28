//
//  StateDelta.swift
//  Woodcase
//

/// A set of property changes at a specific node path within a component's tree.
public struct StateDelta: Friendly {
    public init(nodePath: String, changes: [PropertyChange]) {
        self.nodePath = nodePath
        self.changes = changes
    }

    /// The path to the affected node (e.g., `"."` for root, `"Background"`, `"Header/Title"`).
    public var nodePath: String

    /// The property changes at this node.
    public var changes: [PropertyChange]
}

/// A single pen-level property change within a state variant.
public struct PropertyChange: Friendly {
    /// A change to `property` whose value is the diff's pen-level encoding.
    ///
    /// A ``DeltaProperty/transform`` change is typed: make it with ``init(transform:)``.
    public init(property: DeltaProperty, value: AnyCodable) {
        self.property = property
        self.value = .encoded(value)
    }

    /// A ``DeltaProperty/transform`` change to `transform`.
    public init(transform: DeltaTransform) {
        property = .transform
        value = .transform(transform)
    }

    /// Which visual property changed.
    public var property: DeltaProperty

    /// The variant's value for this property.
    public var value: DeltaValue
}

/// Pen-level property identifiers for state deltas.
///
/// These are platform-neutral — each emitter maps them to its target's property names.
public enum DeltaProperty: String, Friendly {
    case fills
    case strokeColor
    case strokeWidth
    case cornerRadius
    case opacity
    case width
    case height
    case padding
    case gap
    case textColor
    case fontSize
    case fontWeight
    case shadow
    case blur
    case transform
}
