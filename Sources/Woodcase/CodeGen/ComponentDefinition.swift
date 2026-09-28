//
//  ComponentDefinition.swift
//  Woodcase
//

/// A reusable component extracted from a .pen document for code generation.
///
/// Each definition captures a component's props, actions, and bindings so that
/// emitters can produce typed, interactive UI code.
public struct ComponentDefinition: Friendly {
    public init(
        id: String,
        name: String,
        sourceNode: PenNode,
        props: [PropDefinition],
        actions: [ActionDefinition],
        bindings: [BindingDefinition],
        role: ComponentRole? = nil,
        states: [StateDefinition] = [],
        variantIDs: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.sourceNode = sourceNode
        self.props = props
        self.actions = actions
        self.bindings = bindings
        self.role = role
        self.states = states
        self.variantIDs = variantIDs
    }

    /// The source node ID.
    public var id: String

    /// Sanitized component name (e.g., "StatCard").
    public var name: String

    /// The reusable node itself.
    public var sourceNode: PenNode

    /// Props derived from `_props` metadata.
    public var props: [PropDefinition]

    /// Actions derived from `_role` on this node or a descendant, named by `_action`
    /// where one is written and `click` by default on a `button` or a `link`.
    ///
    /// Collected but not yet emitted: no emitter reads this.
    public var actions: [ActionDefinition]

    /// Bindings derived from `_role` alone — a `textInput`, `toggle` or `select` node
    /// becomes one, named after the node. There is no `_bind` key; nothing reads one.
    ///
    /// Collected but not yet emitted: no emitter reads this.
    public var bindings: [BindingDefinition]

    /// The interactive role of this component (e.g., button, toggle).
    ///
    /// Read from `_role` on the reusable node's own root only. `_role` on a descendant
    /// contributes an action or a binding instead, and never sets this.
    public var role: ComponentRole?

    /// Interactive state definitions for this component.
    public var states: [StateDefinition]

    /// Maps state name to variant node ID for tabBar ref resolution (e.g., "home" -> "YabBu").
    public var variantIDs: [String: String] = [:]

    /// Fast lookup from node ID to the props that read that node, for matching ref
    /// override keys.
    ///
    /// One descendant may carry several props — a `label` reading a text node's content
    /// and a `tint` reading its fill are two readings of one node — so this is
    /// one-to-many rather than one-to-one. Each node's props are ordered by prop name, so
    /// that where two props of one node read the same field the emitter's "keep the
    /// first" is a property of the document rather than of the order the props were
    /// built in; `lint` reports that ambiguity under `codegen-prop-path`. A prop whose
    /// path resolved to nothing has no ``PropDefinition/targetNodeID`` and so appears
    /// here under no key at all.
    public var propsByNodeID: [String: [PropDefinition]] {
        var lookup: [String: [PropDefinition]] = [:]
        for prop in props {
            guard let nodeID = prop.targetNodeID else { continue }
            lookup[nodeID, default: []].append(prop)
        }
        return lookup.mapValues { $0.sorted { $0.name < $1.name } }
    }
}

/// A prop exposed by a component, mapping a name to a descendant node's content.
public struct PropDefinition: Friendly {
    public init(
        name: String,
        path: String,
        type: PropType,
        defaultValue: AnyCodable?,
        targetNodeID: String? = nil
    ) {
        self.name = name
        self.path = path
        self.type = type
        self.defaultValue = defaultValue
        self.targetNodeID = targetNodeID
    }

    /// Prop name (e.g., "title").
    public var name: String

    /// Descendant path (e.g., "Header/Title").
    public var path: String

    /// Inferred type from the target node.
    public var type: PropType

    /// Current value from the source node.
    public var defaultValue: AnyCodable?

    /// The ID of the resolved descendant node, used to match ref override keys.
    public var targetNodeID: String?
}

/// The inferred type of a component prop.
public enum PropType: String, Friendly {
    /// Text node content.
    case string
    /// Fill color.
    case color
    /// Enabled/visibility toggle.
    case boolean
    /// Image fill URL.
    case imageURL
}

/// An interactive action declared on a component descendant.
public struct ActionDefinition: Friendly {
    public init(
        name: String,
        role: String,
        nodeID: String
    ) {
        self.name = name
        self.role = role
        self.nodeID = nodeID
    }

    /// Action name (e.g., "submit").
    public var name: String

    /// The `_role` value (e.g., "button").
    public var role: String

    /// Node that declares the action.
    public var nodeID: String
}

/// A two-way binding declared on a component descendant.
public struct BindingDefinition: Friendly {
    public init(
        name: String,
        role: String,
        nodeID: String,
        valueType: PropType
    ) {
        self.name = name
        self.role = role
        self.nodeID = nodeID
        self.valueType = valueType
    }

    /// Binding name (e.g., "email").
    public var name: String

    /// The `_role` value (e.g., "textInput").
    public var role: String

    /// Node that declares the binding.
    public var nodeID: String

    /// Inferred type for the bound value.
    public var valueType: PropType
}
