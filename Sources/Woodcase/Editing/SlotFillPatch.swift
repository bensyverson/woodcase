//
//  SlotFillPatch.swift
//  Woodcase
//

import Foundation

/// One override's change, carried into the slot fill that holds the node it names.
///
/// A slot fill is inline .pen JSON — a `children` value in a ref's `descendants` map —
/// so the node an instance wrote there has no storage of its own to patch. This finds it
/// in that JSON and changes it the way ``PenNodePatcher`` would have applied the
/// override, leaving every other byte of the fill as written. Working on the JSON rather
/// than a decoded ``PenNode`` is deliberate: a round trip through the model would
/// normalize the fill's other nodes, and the write is about one of them.
///
/// It is the mechanics only. Whether a key names content an instance wrote into its own
/// slot is ``EditableDocument/ownSlotContentKeys(ofInstance:)``'s answer; see
/// ``EditableDocument/slotFillRewrite(of:)``.
struct SlotFillPatch: Friendly {
    /// The keys the override writes, raw .pen names.
    var properties: [String: AnyCodable]

    /// The keys the override removes.
    var unset: [String]

    /// A fill found and rewritten: the `descendants` key that carries it, and its new
    /// `children`.
    struct Rewritten: Friendly {
        /// The `descendants` key whose `children` hold the node.
        var key: String

        /// The `children` list with the node changed.
        var children: [AnyCodable]
    }

    /// The JSON key naming a node.
    private static let idKey = "id"

    /// The JSON key holding a ref's overrides.
    private static let descendantsKey = "descendants"

    /// The `type` value of an instance.
    private static let refType = "ref"

    /// Rewrites the fill that holds the node a key names, among one ref's overrides.
    ///
    /// A fill keyed `Inn/Hole` holds nodes under the key prefix `Inn/`: the injected
    /// node's key is that prefix and its own id, however deep it sits in the fill. So a
    /// fill is a candidate when its key, less its last step, is a prefix of the steps.
    ///
    /// - Parameters:
    ///   - fills: The ref's `descendants` map, each entry's properties as JSON.
    ///   - steps: The key's `/`-separated steps.
    /// - Returns: The rewritten fill, or `nil` when no fill holds the node.
    func rewrite(fills: [String: [String: AnyCodable]], steps: [String]) -> Rewritten? {
        for key in fills.keys.sorted() {
            guard case let .array(children)? = fills[key]?[PenNodePatcher.childrenKey] else { continue }
            let prefix = key.split(separator: NodeAddress.separator).map(String.init).dropLast()
            guard steps.count > prefix.count, steps.starts(with: prefix) else { continue }
            if let rewritten = rewrite(children, steps: Array(steps.dropFirst(prefix.count))) {
                return Rewritten(key: key, children: rewritten)
            }
        }
        return nil
    }

    // MARK: - Private

    /// Rewrites the node the steps name within one list of node JSONs, searching the
    /// inline children of every non-instance node — an instance's nodes answer to a
    /// longer key.
    private func rewrite(_ nodes: [AnyCodable], steps: [String]) -> [AnyCodable]? {
        guard let first = steps.first else { return nil }
        var nodes = nodes
        for index in nodes.indices {
            guard case var .dictionary(node) = nodes[index] else { continue }
            if node[Self.idKey] == .string(first) {
                guard let patched = rewrite(node, within: Array(steps.dropFirst())) else { return nil }
                nodes[index] = .dictionary(patched)
                return nodes
            }
            guard node[PenDescendantOverride.typeKey] != .string(Self.refType),
                  case let .array(children)? = node[PenNodePatcher.childrenKey],
                  let rewritten = rewrite(children, steps: steps)
            else { continue }
            node[PenNodePatcher.childrenKey] = .array(rewritten)
            nodes[index] = .dictionary(node)
            return nodes
        }
        return nil
    }

    /// Applies the change to a found node, or — when steps remain — to what that node,
    /// an injected instance, holds.
    ///
    /// Inside an injected instance the remaining steps name either content *it* wrote
    /// into its own slot, rewritten into that fill in turn, or a node of its component,
    /// which is an ordinary key of its own `descendants`.
    private func rewrite(_ node: [String: AnyCodable], within rest: [String]) -> [String: AnyCodable]? {
        guard !rest.isEmpty else { return patched(node) }
        guard node[PenDescendantOverride.typeKey] == .string(Self.refType) else { return nil }

        var result = node
        var map: [String: AnyCodable] = [:]
        if case let .dictionary(existing)? = node[Self.descendantsKey] { map = existing }
        let fills = map.compactMapValues { value -> [String: AnyCodable]? in
            guard case let .dictionary(entry) = value else { return nil }
            return entry
        }
        if let inner = rewrite(fills: fills, steps: rest) {
            var entry = fills[inner.key] ?? [:]
            entry[PenNodePatcher.childrenKey] = .array(inner.children)
            map[inner.key] = .dictionary(entry)
        } else {
            let key = rest.joined(separator: String(NodeAddress.separator))
            let merged = EditableDocument.merging(properties, into: fills[key] ?? [:], removing: unset)
            map[key] = merged.isEmpty ? nil : .dictionary(merged)
        }
        result[Self.descendantsKey] = map.isEmpty ? nil : .dictionary(map)
        return result
    }

    /// The node with the change applied as ``PenNodePatcher`` applies an override: a
    /// `type` key replaces it whole, keeping its id; any other key overwrites its own;
    /// then the unset keys go.
    private func patched(_ node: [String: AnyCodable]) -> [String: AnyCodable] {
        var result = node
        if properties[PenDescendantOverride.typeKey] != nil {
            result = properties
            result[Self.idKey] = node[Self.idKey]
        } else {
            result.merge(properties) { _, new in new }
        }
        for key in unset {
            result.removeValue(forKey: key)
        }
        return result
    }
}
