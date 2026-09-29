//
//  InstanceOverrides.swift
//  Woodcase
//

import Foundation

/// How one instance's overrides stand against its component's props: which the props
/// carry, which change nothing, and which only an inlined copy of the component can draw.
///
/// An instance is a call to its component exactly when every override is one of the
/// first two. A property an override sets is **carried** when a prop reads it — a text
/// prop the node's `content`, a color or image prop its `fill` (a node of one fill: the
/// override replaces them all, the prop only the one it reads), a boolean prop its
/// `enabled` — and ``PropMapper`` finds a value in it. It **changes nothing** when patching
/// it onto the node leaves the node as it was, when it sizes the node the way it was
/// already sized (`fit_content` over an unset height), or when it is an `x` or `y` on a
/// node its parent lays out, which Pen ignores. The instance's own `width` and `height`,
/// where they size the root differently, are its ``rootWidth`` and ``rootHeight``: whether
/// a call can place a resized root is the target's to say. The `children` an override writes into a
/// frame the emitter declares as a slot are that slot's **fill**, which a call passes as
/// the slot's content. Anything else — a path into a nested instance, a whole-node
/// replacement, children written anywhere else, a node the component does not hold — is
/// **unmapped**.
///
/// Target-neutral: it reads the document model and ``PropMapper`` and formats nothing.
/// ``SwiftUIEmitter`` inlines an instance with anything unmapped, or a resized root no
/// frame at the call can size. React is looser: it
/// inlines only for a key no prop names, and drops the other properties of a key one
/// does.
struct InstanceOverrides: Friendly {
    /// The prop values the overrides set, in prop-name order, without those equal to the
    /// prop's default.
    var arguments: [PropMapper.MappedProp] = []

    /// What no prop carries and changes the drawing, sorted: a descendant's id, or a
    /// root property's name.
    var unmapped: [String] = []

    /// The nodes the overrides write into the component's slots, by slot frame id.
    var slotFills: [String: [PenNode]] = [:]

    /// The sizing the instance's own `width` gives the component's root, when it sizes it
    /// differently; the target places the resized root or refuses it.
    var rootWidth: PenSizing?

    /// The sizing the instance's own `height` gives the component's root, when it sizes it
    /// differently.
    var rootHeight: PenSizing?

    /// Sort `data`'s overrides against `component`, whose ``ComponentDefinition/props``
    /// are the props its emitted code can take and whose frames `slots`, by id, the slots
    /// its emitted code can fill.
    init(of data: PenNode.RefData, against component: ComponentDefinition, slots: Set<String> = []) {
        let root = component.sourceNode
        var unmapped: Set<String> = []
        for (key, value) in data.rootOverrides ?? [:] where !Self.isNoOp(key, value, on: root, inFlow: false) {
            let resized = PenNodePatcher.patchNode(root, with: [key: value])
            switch key {
            case PropertyKey.width: rootWidth = PenLayoutEngine.widthSizing(of: resized)
            case PropertyKey.height: rootHeight = PenLayoutEngine.heightSizing(of: resized)
            default: unmapped.insert(key)
            }
        }

        let descendants = data.descendants ?? [:]
        let mapped = PropMapper.map(overrides: descendants, to: component)
        let props = Dictionary(component.props.map { ($0.name, $0) }) { first, _ in first }
        var carried: Set<Field> = []
        for argument in mapped {
            guard let prop = props[argument.name], let nodeID = prop.targetNodeID else { continue }
            carried.insert(Field(nodeID: nodeID, key: Self.key(for: prop.type)))
        }

        let placed = Self.placedNodes(in: root)
        for (id, override) in descendants {
            guard let (node, inFlow) = placed[id], !override.isObjectReplacement else {
                unmapped.insert(id)
                continue
            }
            for (key, value) in override.properties {
                if key == PenNodePatcher.childrenKey, slots.contains(id), let children = Self.nodes(in: value) {
                    slotFills[id] = children
                } else if key == PropertyKey.fill, (Self.fillCount(of: node) ?? 0) > 1 {
                    unmapped.insert(id)
                } else if !carried.contains(Field(nodeID: id, key: key)), !Self.isNoOp(key, value, on: node, inFlow: inFlow) {
                    unmapped.insert(id)
                }
            }
        }

        arguments = mapped.filter { argument in
            guard let prop = props[argument.name] else { return false }
            return !Self.isDefault(argument.value, of: prop)
        }
        self.unmapped = unmapped.sorted()
    }

    // MARK: - Reading

    /// One property of one node.
    private struct Field: Hashable {
        /// The node's id.
        var nodeID: String
        /// The property's key.
        var key: String
    }

    /// The keys an override is judged by.
    private enum PropertyKey {
        /// A text node's copy, which a text prop reads.
        static let content = "content"
        /// A node's paints, which a color or image prop reads.
        static let fill = "fill"
        /// A node's switch, which a boolean prop reads.
        static let enabled = "enabled"
        /// The horizontal position, which a laid-out node ignores.
        static let x = "x"
        /// The vertical position, which a laid-out node ignores.
        static let y = "y"
        /// The width, judged by the sizing it gives.
        static let width = "width"
        /// The height, judged by the sizing it gives.
        static let height = "height"
    }

    /// The property a prop of `type` reads.
    private static func key(for type: PropType) -> String {
        switch type {
        case .string: PropertyKey.content
        case .color, .imageURL: PropertyKey.fill
        case .boolean: PropertyKey.enabled
        }
    }

    /// Whether setting `key` to `value` on `node` changes nothing Pen draws.
    private static func isNoOp(_ key: String, _ value: AnyCodable, on node: PenNode, inFlow: Bool) -> Bool {
        if inFlow, key == PropertyKey.x || key == PropertyKey.y {
            return true
        }
        let patched = PenNodePatcher.patchNode(node, with: [key: value])
        switch key {
        case PropertyKey.width:
            return PenLayoutEngine.widthSizing(of: patched) == PenLayoutEngine.widthSizing(of: node)
        case PropertyKey.height:
            return PenLayoutEngine.heightSizing(of: patched) == PenLayoutEngine.heightSizing(of: node)
        default:
            return patched == node
        }
    }

    /// `value` read as a list of nodes, or `nil` when it is not one.
    private static func nodes(in value: AnyCodable) -> [PenNode]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode([PenNode].self, from: data)
    }

    /// Whether `value` is what `prop` already holds.
    private static func isDefault(_ value: PropMapper.Value, of prop: PropDefinition) -> Bool {
        switch (value, prop.defaultValue) {
        case let (.string(text), .string(current)?): text == current
        case let (.color(.literal(hex)), .string(current)?): hex == current
        case let (.color(.variable(name)), .string(current)?): current == "$\(name)"
        case let (.imageURL(url), .string(current)?): url == current
        case let (.boolean(flag), .bool(current)?): flag == current
        default: false
        }
    }

    /// How many fills `node` carries, or `nil` for a kind without fills.
    private static func fillCount(of node: PenNode) -> Int? {
        switch node.kind {
        case let .frame(data): data.fills?.all.count
        case let .rectangle(data): data.fills?.all.count
        case let .ellipse(data): data.fills?.all.count
        case let .text(data): data.fills?.all.count
        default: nil
        }
    }

    /// Every node the component's own tree holds, by id, with whether its parent lays it
    /// out — nodes inside nested instances are the nested components', and not here.
    private static func placedNodes(in root: PenNode) -> [String: (node: PenNode, inFlow: Bool)] {
        var nodes: [String: (node: PenNode, inFlow: Bool)] = [:]
        var pending: [(node: PenNode, inFlow: Bool)] = [(root, false)]
        while let (node, inFlow) = pending.popLast() {
            nodes[node.id] = (node, inFlow)
            let laysOut: Bool = if case let .frame(data) = node.kind { (data.layout ?? .horizontal) != .none } else { false }
            for child in node.kind.inlineChildrenIfPresent ?? [] {
                pending.append((child, laysOut && child.common.layoutPosition != .absolute))
            }
        }
        return nodes
    }
}
