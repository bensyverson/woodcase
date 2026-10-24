//
//  SlotJSON.swift
//  Woodcase
//

import Foundation

/// The node JSON a slot fill holds, read and rewritten in place.
///
/// A fill is inline .pen JSON — the `children` value of a `descendants` entry — so the
/// nodes in it have no storage of their own. A structural edit on a fill takes nodes out
/// of that list, puts nodes into it, or reorders it, and leaves every other node's bytes
/// as written: only a node the edit itself changes goes through the model
/// (``node(from:)`` and ``json(of:)``). The search for a node by id walks the inline
/// `children` of frames and groups, never into an instance: the nodes of the component
/// an instance places are not in its fill, and a fill *it* writes answers to a longer
/// location (``SlotFillLocation``).
enum SlotJSON {
    /// The JSON key naming a node.
    static let idKey = "id"

    /// The JSON key holding a container's children, and a fill's content.
    static let childrenKey = PenNodePatcher.childrenKey

    /// The JSON key holding a ref's overrides.
    static let descendantsKey = "descendants"

    /// The `type` value of an instance.
    static let refType = "ref"

    // MARK: - Reading

    /// The id a node JSON carries, or `nil` for something that is not a node.
    static func id(of value: AnyCodable) -> String? {
        guard case let .dictionary(node) = value, case let .string(id)? = node[idKey] else { return nil }
        return id
    }

    /// Whether a node JSON is an instance.
    static func isRef(_ node: [String: AnyCodable]) -> Bool {
        node[PenDescendantOverride.typeKey] == .string(refType)
    }

    /// The inline children a node JSON holds, or `nil` for one that declares none.
    static func children(of node: [String: AnyCodable]) -> [AnyCodable]? {
        guard case let .array(children)? = node[childrenKey] else { return nil }
        return children
    }

    /// The node with this id anywhere in a list, searching the inline children of every
    /// node that is not an instance.
    ///
    /// - Parameters:
    ///   - id: The node's id.
    ///   - list: The node JSONs to search.
    /// - Returns: The node, or `nil` when the list holds none of that id.
    static func node(_ id: String, in list: [AnyCodable]) -> [String: AnyCodable]? {
        for case let .dictionary(node) in list {
            if node[idKey] == .string(id) { return node }
            guard !isRef(node), let children = children(of: node), let found = self.node(id, in: children)
            else { continue }
            return found
        }
        return nil
    }

    /// Where a node sits in a list: its parent's id (`nil` for the list itself) and its
    /// index among its siblings.
    ///
    /// - Parameters:
    ///   - id: The node's id.
    ///   - list: The node JSONs to search.
    /// - Returns: The parent and index, or `nil` when the list holds no such node.
    static func position(of id: String, in list: [AnyCodable]) -> (parentID: String?, index: Int)? {
        position(of: id, in: list, parentID: nil)
    }

    /// The children of a container in a list, or of the list itself for `nil`.
    ///
    /// - Parameters:
    ///   - containerID: The container's id, or `nil` for the list.
    ///   - list: The node JSONs.
    /// - Returns: The children, or `nil` when no such container is in the list. A
    ///   container that declares no children answers an empty list.
    static func children(of containerID: String?, in list: [AnyCodable]) -> [AnyCodable]? {
        guard let containerID else { return list }
        guard let container = node(containerID, in: list) else { return nil }
        return children(of: container) ?? []
    }

    /// Every id in a list of node JSONs, at every depth — the inline children of every
    /// node, and every node in the fills an instance among them writes.
    ///
    /// - Parameter list: The node JSONs.
    /// - Returns: The ids, in tree order.
    static func allIDs(in list: [AnyCodable]) -> [String] {
        var result: [String] = []
        var pending = Array(list.reversed())
        while let next = pending.popLast() {
            guard case let .dictionary(node) = next else { continue }
            if case let .string(id)? = node[idKey] { result.append(id) }
            var nested: [AnyCodable] = children(of: node) ?? []
            if case let .dictionary(map)? = node[descendantsKey] {
                for key in map.keys.sorted() {
                    guard case let .dictionary(entry)? = map[key], case let .array(fill)? = entry[childrenKey]
                    else { continue }
                    nested.append(contentsOf: fill)
                }
            }
            pending.append(contentsOf: nested.reversed())
        }
        return result
    }

    // MARK: - Rewriting

    /// Takes a node out of a list.
    ///
    /// - Parameters:
    ///   - id: The node's id.
    ///   - list: The node JSONs, rewritten in place.
    /// - Returns: The node taken out, or `nil` when the list holds no such node.
    static func remove(_ id: String, from list: inout [AnyCodable]) -> AnyCodable? {
        for index in list.indices {
            guard case var .dictionary(node) = list[index] else { continue }
            if node[idKey] == .string(id) { return list.remove(at: index) }
            guard !isRef(node), var children = children(of: node),
                  let removed = remove(id, from: &children)
            else { continue }
            node[childrenKey] = .array(children)
            list[index] = .dictionary(node)
            return removed
        }
        return nil
    }

    /// Puts a node into a container in a list, or into the list itself.
    ///
    /// - Parameters:
    ///   - node: The node JSON to insert.
    ///   - containerID: The container's id, or `nil` for the list.
    ///   - index: Where among the children it goes; `nil`, or past the end, puts it last.
    ///   - list: The node JSONs, rewritten in place.
    /// - Returns: `false` when no such container is in the list.
    @discardableResult
    static func insert(
        _ node: AnyCodable,
        into containerID: String?,
        at index: Int?,
        in list: inout [AnyCodable]
    ) -> Bool {
        guard let containerID else {
            list.insert(node, at: min(index ?? list.count, list.count))
            return true
        }
        return replace(containerID, in: &list) { container in
            var children = children(of: container) ?? []
            children.insert(node, at: min(index ?? children.count, children.count))
            container[childrenKey] = .array(children)
        }
    }

    /// Rewrites one node of a list in place.
    ///
    /// - Parameters:
    ///   - id: The node's id.
    ///   - list: The node JSONs, rewritten in place.
    ///   - body: Changes the node.
    /// - Returns: `false` when the list holds no such node.
    @discardableResult
    static func replace(
        _ id: String,
        in list: inout [AnyCodable],
        _ body: (inout [String: AnyCodable]) -> Void
    ) -> Bool {
        for index in list.indices {
            guard case var .dictionary(node) = list[index] else { continue }
            if node[idKey] == .string(id) {
                body(&node)
                list[index] = .dictionary(node)
                return true
            }
            guard !isRef(node), var children = children(of: node), replace(id, in: &children, body)
            else { continue }
            node[childrenKey] = .array(children)
            list[index] = .dictionary(node)
            return true
        }
        return false
    }

    // MARK: - Through the model

    /// A node JSON decoded, or `nil` for one the model cannot read.
    static func node(from value: AnyCodable) -> PenNode? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(PenNode.self, from: data)
    }

    /// A node encoded as the JSON a fill holds.
    ///
    /// - Parameter node: The node, with its children inline.
    /// - Returns: Its JSON.
    /// - Throws: An encoding error, which a node the model holds never raises.
    static func json(of node: PenNode) throws -> AnyCodable {
        try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(node))
    }

    // MARK: - Private

    /// ``position(of:in:)``, one level down.
    private static func position(
        of id: String, in list: [AnyCodable], parentID: String?
    ) -> (parentID: String?, index: Int)? {
        for (index, value) in list.enumerated() {
            guard case let .dictionary(node) = value else { continue }
            if node[idKey] == .string(id) { return (parentID, index) }
            guard !isRef(node), let children = children(of: node), case let .string(own)? = node[idKey],
                  let found = position(of: id, in: children, parentID: own)
            else { continue }
            return found
        }
        return nil
    }
}
