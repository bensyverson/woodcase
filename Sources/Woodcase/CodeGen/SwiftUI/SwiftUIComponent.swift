//
//  SwiftUIComponent.swift
//  Woodcase
//

/// A reusable component as the SwiftUI emitter writes it: a view struct's name, the
/// props its body can read and the slots a caller fills.
struct SwiftUIComponent: Friendly {
    /// The analyzed component.
    var definition: ComponentDefinition

    /// The view struct's name, unique in the module.
    var typeName: String

    /// The props the struct declares, in the analyzer's order (by name).
    var props: [SwiftUIProp]

    /// The analyzed props the body cannot read, which the struct leaves out.
    var unbound: [PropDefinition]

    /// What the props' defaults could not write, for the component's warning.
    var unemitted: [String]

    /// The slots the struct takes content for, in document order.
    var slots: [SwiftUISlot]

    /// The frames marked `slot` the struct draws as plain frames, for the component's warning.
    var refusedSlots: [SwiftUISlot.Refusal]

    /// The analyzed props read inside a slot's default content, which a caller's content
    /// replaces; the struct leaves them out.
    var slotted: [PropDefinition]

    /// The component `definition`, named `typeName`, its props bound where its tree lets
    /// the body read them; a colour prop may default to a variable of `theme`.
    init(_ definition: ComponentDefinition, typeName: String, theme: SwiftUITheme? = nil) {
        self.definition = definition
        self.typeName = typeName
        let nodes = Self.nodesByID(in: definition.sourceNode)
        var props: [SwiftUIProp] = []
        var unbound: [PropDefinition] = []
        var unemitted: [String] = []
        let control = SwiftUIControl(definition)
        let taken = Set(definition.props.map { SwiftUIProp.identifier($0.name) })
            .union(control?.memberNames ?? []).union(control?.faces.map(\.property) ?? [])
        let found = SwiftUISlot.slots(in: definition.sourceNode, typeName: typeName, taken: taken)
        let inDefaults = Set(found.slots.flatMap { $0.defaultContent.flatMap { Self.nodesByID(in: $0).keys } })
        var slotted: [PropDefinition] = []
        for prop in definition.props {
            if let target = prop.targetNodeID, inDefaults.contains(target) {
                slotted.append(prop)
            } else if let bound = SwiftUIProp(prop, target: prop.targetNodeID.flatMap { nodes[$0] }, theme: theme, unemitted: &unemitted) {
                props.append(bound)
            } else {
                unbound.append(prop)
            }
        }
        self.props = props
        self.unbound = unbound
        self.unemitted = unemitted
        slots = found.slots
        refusedSlots = found.refused
        self.slotted = slotted
    }

    /// The definition with only the props the struct declares: what an instance's
    /// overrides are measured against (``InstanceOverrides``).
    var bindable: ComponentDefinition {
        var copy = definition
        let names = Set(props.map(\.definition.name))
        copy.props = definition.props.filter { names.contains($0.name) }
        return copy
    }

    /// The struct's props by the id of the node each is read at.
    var propsByNodeID: [String: [SwiftUIProp]] {
        Dictionary(grouping: props) { $0.definition.targetNodeID ?? "" }
    }

    /// The struct's slots by the id of their frame.
    var slotsByNodeID: [String: SwiftUISlot] {
        Dictionary(slots.map { ($0.frame.id, $0) }) { first, _ in first }
    }

    /// The nodes of the component's own tree, by id; nested instances' nodes are theirs.
    private static func nodesByID(in root: PenNode) -> [String: PenNode] {
        var nodes: [String: PenNode] = [:]
        var pending = [root]
        while let node = pending.popLast() {
            nodes[node.id] = node
            pending.append(contentsOf: node.kind.inlineChildrenIfPresent ?? [])
        }
        return nodes
    }
}
