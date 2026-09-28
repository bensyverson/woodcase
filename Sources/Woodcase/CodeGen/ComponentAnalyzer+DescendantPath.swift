//
//  ComponentAnalyzer+DescendantPath.swift
//  Woodcase
//

import Foundation

/// The one rule that turns a `common.metadata._props` path into the descendant it names.
///
/// A `_props` entry is `{"<prop name>": "<path>"}`, and the path is a run of `/`-separated
/// child *names* starting at the component's own children — `"Label"`, `"Row/Title"`.
/// ``ComponentAnalyzer`` resolves it as it extracts a component's props, to give each
/// prop its target node; `codegen-prop-path` (`DocumentLinter+CodegenPropPath.swift`)
/// resolves it to ask whether it lands anywhere at all. Both call this, so a path the
/// lint calls good is a path
/// codegen wires, and the two cannot drift apart — the reason it lives here rather than
/// being re-derived on the lint side.
public extension ComponentAnalyzer {
    /// The descendant a `_props` path names.
    ///
    /// - Parameters:
    ///   - path: The `/`-separated run of child names, relative to `node`'s own children.
    ///   - node: The component's root, materialized with its children.
    /// - Returns: The node the last segment names, or `nil` when any segment names no
    ///   child of the one before it. An empty path names nothing.
    static func resolveDescendantPath(_ path: String, from node: PenNode) -> PenNode? {
        let segments = path.split(separator: "/").map(String.init)
        var current: PenNode?
        var searchChildren: [PenNode] = childNodes(of: node)
        for segment in segments {
            current = searchChildren.first { $0.common.name == segment }
            guard let found = current else { return nil }
            searchChildren = childNodes(of: found)
        }
        return current
    }

    /// A node's inline children, empty for a kind that holds none.
    ///
    /// A `ref` holds none: an instance's children come from the component it names, and
    /// neither the analyzer nor the linter expands one while resolving a path, so a
    /// `_props` path never reaches into a nested component.
    static func childNodes(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }
}
