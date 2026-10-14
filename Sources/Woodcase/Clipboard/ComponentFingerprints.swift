//
//  ComponentFingerprints.swift
//  Woodcase
//

import Foundation

/// Component definitions read so that two documents' copies of one component compare
/// equal — what a paste means by "the same definition".
///
/// A definition is its stored subtree, every property of every node, with four things
/// read in a document-neutral way:
///
/// - **Its own node ids** become their pre-order position (`#0` for the root), because a
///   paste regenerates ids: the `Button` one paste brought into a document has different
///   ids from the source's, and is still the same definition.
/// - **A component it renders** — a `ref`'s target, a repointed `ref` in an override — is
///   read as that component's own fingerprint, so two definitions are equal only when
///   the components they draw are equal too, whatever their ids.
/// - **A `descendants` key** names nodes inside the component an instance draws; each
///   segment is read as its position in that component (and the next segment in the
///   component *that* node draws, for a nested path).
/// - **A `$name`** is read through the caller's variable map, so a definition that uses a
///   variable the paste renames is not equal to one that uses the target's.
///
/// The root's `x` and `y` are left out: where a definition sits on the canvas is not
/// part of what it is, and a paste places definitions it brings anew.
struct ComponentFingerprints {
    /// Creates a reader over one document's components.
    ///
    /// - Parameters:
    ///   - registry: Component id → the component's whole subtree.
    ///   - variables: Variable name → the name to read it as.
    init(registry: [String: PenNode], variables: @escaping (String) -> String) {
        self.registry = registry
        self.variables = variables
    }

    /// The canonical text of a component's definition, or `nil` when the registry has no
    /// such component. Two components are the same definition when their texts are equal.
    ///
    /// - Parameter id: The component's id.
    /// - Returns: The text.
    mutating func text(of id: String) -> String? {
        if let known = texts[id] { return known }
        guard let component = registry[id] else { return nil }
        guard visiting.insert(id).inserted else { return Self.loopMarker }
        defer { visiting.remove(id) }
        let positions = positions(in: id)
        guard let json = try? JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(component)) else {
            return nil
        }
        let canonical = node(json, positions: positions, isRoot: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = (try? encoder.encode(canonical)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        texts[id] = text
        return text
    }

    // MARK: - State

    /// Component id → its subtree.
    private let registry: [String: PenNode]

    /// Variable name → the name to read it as.
    private let variables: (String) -> String

    /// The texts worked out so far.
    private var texts: [String: String] = [:]

    /// Each component's nodes by id: their pre-order position and the node.
    private var indexes: [String: [String: (position: Int, node: PenNode)]] = [:]

    /// The components whose text is being worked out, so a loop reads as a marker
    /// instead of recursing forever.
    private var visiting: Set<String> = []

    /// What a component reads as inside its own definition, through a loop.
    private static let loopMarker = "loop"

    // MARK: - Reading

    /// Each node of a component by id, with its pre-order position.
    private mutating func positions(in id: String) -> [String: (position: Int, node: PenNode)] {
        if let known = indexes[id] { return known }
        var result: [String: (position: Int, node: PenNode)] = [:]
        var pending = registry[id].map { [$0] } ?? []
        var position = 0
        while let node = pending.popLast() {
            result[node.id] = (position, node)
            position += 1
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        indexes[id] = result
        return result
    }

    /// A node's JSON, read canonically.
    private mutating func node(
        _ value: AnyCodable,
        positions: [String: (position: Int, node: PenNode)],
        isRoot: Bool = false
    ) -> AnyCodable {
        guard case let .dictionary(entries) = value else { return renamed(value) }
        let isRef = entries[Key.type] == .string(Key.ref)
        var target: String?
        if isRef, case let .string(ref)? = entries[Key.ref] {
            target = ref
        }
        var result: [String: AnyCodable] = [:]
        for (key, entry) in entries {
            if isRoot, key == Key.x || key == Key.y { continue }
            switch key {
            case Key.id:
                result[key] = local(entry, positions: positions)
            case Key.children:
                guard case let .array(items) = entry else { result[key] = entry; continue }
                result[key] = .array(items.map { node($0, positions: positions) })
            case Key.ref where isRef:
                result[key] = reference(entry, positions: positions)
            case Key.descendants:
                result[key] = overrides(entry, drawing: target, positions: positions)
            default:
                result[key] = renamed(entry)
            }
        }
        return .dictionary(result)
    }

    /// A `descendants` map, its keys read as positions in the component drawn.
    private mutating func overrides(
        _ value: AnyCodable,
        drawing component: String?,
        positions: [String: (position: Int, node: PenNode)]
    ) -> AnyCodable {
        guard case let .dictionary(entries) = value else { return value }
        var result: [String: AnyCodable] = [:]
        for (key, override) in entries {
            result[path(key, from: component)] = self.override(override, positions: positions)
        }
        return .dictionary(result)
    }

    /// One override, read canonically.
    private mutating func override(
        _ value: AnyCodable,
        positions: [String: (position: Int, node: PenNode)]
    ) -> AnyCodable {
        guard case let .dictionary(entries) = value else { return renamed(value) }
        if entries[PenDescendantOverride.typeKey] != nil {
            return node(value, positions: positions)
        }
        var repointed: String?
        if case let .string(ref)? = entries[Key.ref] {
            repointed = ref
        }
        var result: [String: AnyCodable] = [:]
        for (key, entry) in entries {
            switch key {
            case Key.ref:
                result[key] = reference(entry, positions: positions)
            case Key.descendants:
                result[key] = overrides(entry, drawing: repointed, positions: positions)
            case Key.children:
                guard case let .array(items) = entry else { result[key] = entry; continue }
                result[key] = .array(items.map { node($0, positions: positions) })
            default:
                result[key] = renamed(entry)
            }
        }
        return .dictionary(result)
    }

    /// A node id of the definition itself, as its position.
    private func local(_ value: AnyCodable, positions: [String: (position: Int, node: PenNode)]) -> AnyCodable {
        guard case let .string(id) = value, let found = positions[id] else { return value }
        return .string("#\(found.position)")
    }

    /// A component reference: a node of the definition by position, another component by
    /// its fingerprint, anything else as written.
    private mutating func reference(
        _ value: AnyCodable,
        positions: [String: (position: Int, node: PenNode)]
    ) -> AnyCodable {
        guard case let .string(id) = value else { return value }
        if let found = positions[id] { return .string("#\(found.position)") }
        guard let text = text(of: id) else { return .string("?" + id) }
        var hasher = FNV1aHasher()
        hasher.combine(text)
        return .string("@" + String(hasher.finalize(), radix: 16))
    }

    /// A `descendants` key, each segment read as a position in the component it reaches.
    private mutating func path(_ key: String, from component: String?) -> String {
        var current = component
        return key.split(separator: NodeAddress.separator, omittingEmptySubsequences: false).map { segment in
            let id = String(segment)
            guard let component = current, let found = positions(in: component)[id] else {
                current = nil
                return "?" + id
            }
            if case let .ref(data) = found.node.kind {
                current = data.ref
            } else {
                current = nil
            }
            return "#\(found.position)"
        }.joined(separator: String(NodeAddress.separator))
    }

    /// A value with its variable references read through the map.
    private func renamed(_ value: AnyCodable) -> AnyCodable {
        PasteRewriter.renamingVariables(in: value, variables)
    }

    /// The .pen keys the reading treats specially.
    private enum Key {
        static let id = "id"
        static let type = "type"
        static let children = "children"
        static let ref = "ref"
        static let descendants = "descendants"
        static let x = "x"
        static let y = "y"
    }
}
