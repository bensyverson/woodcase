//
//  PasteRewriter.swift
//  Woodcase
//

import Foundation

/// Rewrites what a pasted subtree refers to — node ids, variable names, component
/// names — through the maps a paste settled on.
///
/// It works on the subtree's .pen JSON, so every place the format writes a reference is
/// reached, however deep:
///
/// - **Node ids**: a `ref`'s target; each `/`-separated segment of a `descendants` key;
///   inside an override, a repointed `ref`, nested `descendants`, and the nodes of a
///   `children` list or a whole-node replacement; a connection's endpoint paths. A
///   segment the map does not hold is left as written — it names a node outside the
///   paste.
/// - **Variables**: every string leaf that is `$name` — the rule
///   ``EditableDocument/variableReferences()`` and ``PenClip/extract(nodeIDs:from:documentID:)`` read
///   by — wherever it sits.
/// - **Component names**: a node the paste renames gets its new `name`.
///
/// It never touches a node's own `id`: the caller settles those positionally
/// (``SubtreeIDPlan``) after the rewrite, so an id is mapped exactly once.
///
/// This is the general form of what ``PenImportPrefixer`` does with one alias: that walk
/// is typed and prefixes, this one is a map and reaches every `$name` leaf.
struct PasteRewriter: Friendly {
    /// Old node id → new node id.
    var ids: [String: String]

    /// Old variable name → new name, for the variables renamed.
    var variables: [String: String]

    /// Old node id → the `name` it takes, for the components renamed.
    var names: [String: String]

    /// The subtree with its references rewritten.
    ///
    /// - Parameter node: A subtree of the clip, with the clip's ids.
    /// - Returns: The same subtree, the same shape and ids, referring through the maps.
    /// - Throws: An encoding or decoding error, which a node the library decoded does not
    ///   raise.
    func rewrite(_ node: PenNode) throws -> PenNode {
        let json = try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(node))
        return try JSONDecoder().decode(PenNode.self, from: JSONEncoder().encode(rewritten(node: json)))
    }

    // MARK: - Nodes

    /// One node's JSON, rewritten.
    private func rewritten(node value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(entries) = value else { return renamed(value) }
        let type = Self.string(entries[Key.type])
        let id = Self.string(entries[Key.id])
        for (key, entry) in entries {
            switch key {
            case Key.id:
                continue
            case Key.children:
                entries[key] = rewritten(nodes: entry)
            case Key.ref where type == Key.refType:
                entries[key] = mapped(id: entry)
            case Key.descendants:
                entries[key] = rewritten(overrides: entry)
            case Key.source where type == Key.connectionType, Key.target where type == Key.connectionType:
                entries[key] = rewritten(endpoint: entry)
            default:
                entries[key] = renamed(entry)
            }
        }
        if let id, let name = names[id] {
            entries[Key.name] = .string(name)
        }
        return .dictionary(entries)
    }

    /// A `children` list, each node rewritten.
    private func rewritten(nodes value: AnyCodable) -> AnyCodable {
        guard case let .array(items) = value else { return value }
        return .array(items.map { rewritten(node: $0) })
    }

    /// A connection endpoint, its path's segments mapped.
    private func rewritten(endpoint value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(entries) = value, case let .string(path)? = entries[Key.path] else { return value }
        entries[Key.path] = .string(mapped(path: path))
        return .dictionary(entries)
    }

    // MARK: - Overrides

    /// A `descendants` map: its keys' segments mapped, each override rewritten.
    private func rewritten(overrides value: AnyCodable) -> AnyCodable {
        guard case let .dictionary(entries) = value else { return value }
        var result: [String: AnyCodable] = [:]
        for (key, override) in entries {
            result[mapped(path: key)] = rewritten(override: override)
        }
        return .dictionary(result)
    }

    /// One override: a whole-node replacement is a node; a patch has its repointed
    /// `ref`, nested `descendants` and `children` rewritten, and its variables renamed.
    private func rewritten(override value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(entries) = value else { return renamed(value) }
        if entries[PenDescendantOverride.typeKey] != nil {
            return rewritten(node: value)
        }
        for (key, entry) in entries {
            switch key {
            case Key.ref: entries[key] = mapped(id: entry)
            case Key.descendants: entries[key] = rewritten(overrides: entry)
            case Key.children: entries[key] = rewritten(nodes: entry)
            default: entries[key] = renamed(entry)
            }
        }
        return .dictionary(entries)
    }

    // MARK: - Leaves

    /// A node id, mapped.
    private func mapped(id value: AnyCodable) -> AnyCodable {
        guard case let .string(id) = value, let new = ids[id] else { return value }
        return .string(new)
    }

    /// A `/`-separated path of node ids, each segment mapped.
    private func mapped(path: String) -> String {
        path.split(separator: NodeAddress.separator, omittingEmptySubsequences: false)
            .map { ids[String($0)] ?? String($0) }
            .joined(separator: String(NodeAddress.separator))
    }

    /// A value with its variable references renamed.
    private func renamed(_ value: AnyCodable) -> AnyCodable {
        guard !variables.isEmpty else { return value }
        return Self.renamingVariables(in: value) { variables[$0] ?? $0 }
    }

    /// A value with every `$name` string leaf passed through `rename`.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - rename: Name → the name to write.
    /// - Returns: The value, its references renamed.
    static func renamingVariables(in value: AnyCodable, _ rename: (String) -> String) -> AnyCodable {
        switch value {
        case let .string(text):
            guard text.hasPrefix("$"), text.count > 1 else { return value }
            return .string("$" + rename(String(text.dropFirst())))
        case let .array(items):
            return .array(items.map { renamingVariables(in: $0, rename) })
        case let .dictionary(entries):
            return .dictionary(entries.mapValues { renamingVariables(in: $0, rename) })
        case .null, .bool, .int, .double:
            return value
        }
    }

    /// A JSON value's text, when it is a string.
    private static func string(_ value: AnyCodable?) -> String? {
        guard case let .string(text)? = value else { return nil }
        return text
    }

    /// The .pen keys the rewrite reads.
    private enum Key {
        static let id = "id"
        static let type = "type"
        static let name = "name"
        static let children = "children"
        static let ref = "ref"
        static let descendants = "descendants"
        static let source = "source"
        static let target = "target"
        static let path = "path"
        static let refType = "ref"
        static let connectionType = "connection"
    }
}
