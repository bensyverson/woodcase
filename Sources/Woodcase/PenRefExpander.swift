//
//  PenRefExpander.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Stateless ref expander for .pen documents.
///
/// Builds a component registry from nodes marked `reusable: true`, expands `ref`
/// nodes by cloning their target component and applying descendant overrides, then
/// strips the reusable definitions from the output unless the caller is expanding
/// ``PenRefExpander/Purpose/canvas`` output.
///
/// The expander is pure: it returns a new ``PenDocument`` without mutating the input.
///
/// ```swift
/// let expanded = PenRefExpander.expand(document)
/// let canvas = PenRefExpander.expand(document, for: .canvas)
/// ```
public enum PenRefExpander {
    /// What the expansion's output is for, which decides whether reusable component
    /// definitions survive in the returned tree.
    ///
    /// A definition (`reusable: true`) is a root on the canvas like any other: a design
    /// tool draws it wherever it sits in visible flow, and an agent editing the file has
    /// to be able to see the thing it is editing. Code generation and export have no use
    /// for the template once every instance is a concrete clone, so they strip it.
    public enum Purpose: Friendly {
        /// Design-canvas reading and rendering — `shot`, `tree`, `render`, the viewer.
        /// A definition keeps its place in the tree and gets a rect like any artboard.
        case canvas

        /// Code generation or export. Definitions are stripped: only their instances
        /// (`ref` expansions) belong in generated output.
        case export
    }

    // MARK: - Public API

    /// Expands all ref nodes in the document.
    ///
    /// - Parameters:
    ///   - document: The parsed .pen document (typically after variable resolution).
    ///   - purpose: What the output is for. Defaults to ``Purpose/export``, which
    ///     strips reusable definitions from the result.
    ///   - imported: Components the document's imports define, keyed by prefixed id —
    ///     ``PenImportedDefinitions/registry``. They join the registry and never the
    ///     tree: an instance of one expands, and the definition itself is no root. The
    ///     document's own component wins on an id both hold.
    /// - Returns: A new document with ref nodes replaced by expanded component trees.
    public static func expand(
        _ document: PenDocument,
        for purpose: Purpose = .export,
        imported: [String: PenNode] = [:]
    ) -> PenDocument {
        let registry = buildRegistry(from: document.children).merging(imported) { own, _ in own }

        var result = document
        result.children = expandNodes(
            document.children, registry: registry, visited: [], cache: ResolverCache(),
            strippingDefinitions: purpose == .export
        )
        return result
    }

    /// Expands every ref in a single node's subtree, including the node itself.
    ///
    /// The subtree entry point: the caller supplies the registry, because a subtree
    /// pulled out of a document cannot see the components living elsewhere in it.
    ///
    /// - Parameters:
    ///   - node: The subtree to expand.
    ///   - registry: Component ID → component, as ``buildRegistry(from:)`` builds it.
    /// - Returns: The subtree with its ref nodes replaced by expanded component trees.
    static func expand(_ node: PenNode, registry: [String: PenNode]) -> PenNode {
        expandNodes([node], registry: registry, visited: [], cache: ResolverCache()).first ?? node
    }

    // MARK: - Component Registry

    /// Scans all nodes for `reusable: true` and indexes them by ID.
    ///
    /// On a repeated id the first in document order wins — the node Pen keeps the id
    /// for, since it renames every later one on load.
    static func buildRegistry(from nodes: [PenNode]) -> [String: PenNode] {
        var registry: [String: PenNode] = [:]
        var pending = Array(nodes.reversed())
        while let node = pending.popLast() {
            if node.common.reusable == true, registry[node.id] == nil {
                registry[node.id] = node
            }
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return registry
    }

    // MARK: - Ref Expansion

    /// Walks the node array, expanding every ref node, however deep.
    ///
    /// The walk is ``PenTreeRewrite``'s, so it does not recurse: an instance's clone is
    /// prepared when the walk reaches its `ref`, then walked in turn like any subtree.
    ///
    /// With `strippingDefinitions`, a reusable definition is left out as the walk
    /// reaches it — in the same pass, so no expanded tree is built only to be thrown
    /// away, which in a debug build costs stack as deep as the tree to free.
    private static func expandNodes(
        _ nodes: [PenNode],
        registry: [String: PenNode],
        visited: Set<String>,
        cache: ResolverCache,
        strippingDefinitions: Bool = false
    ) -> [PenNode] {
        PenTreeRewrite.rewrite(nodes, context: visited) { node, visited in
            if strippingDefinitions, node.common.reusable == true { return .drop }
            guard case let .ref(refData) = node.kind else { return .descend(node, visited) }
            guard let instance = prepareInstance(
                refNode: node, refData: refData, registry: registry, visited: visited, cache: cache
            ) else { return .keep(node) }
            return .descend(instance.node, instance.chainVisited)
        }
    }

    /// Expands a single ref node by cloning its target component.
    ///
    /// - Parameters:
    ///   - refNode: The `ref` node.
    ///   - registry: Component id → component.
    ///   - visited: The component ids already on this expansion chain.
    ///   - cache: The override-key resolvers built so far in this expansion.
    /// - Returns: The expanded instance, or `refNode` for a circular or unresolved ref,
    ///   or for a node that is no `ref`.
    static func expandRef(
        refNode: PenNode,
        registry: [String: PenNode],
        visited: Set<String>,
        cache: ResolverCache = ResolverCache()
    ) -> PenNode {
        guard case .ref = refNode.kind else { return refNode }
        return expandNodes([refNode], registry: registry, visited: visited, cache: cache).first ?? refNode
    }

    /// Transfers positional properties from the ref node to the expanded component root.
    /// The ref node's properties take precedence when present.
    static func transferCommonProperties(
        from refCommon: PenNodeCommon,
        to componentCommon: PenNodeCommon
    ) -> PenNodeCommon {
        var result = componentCommon
        if refCommon.name != nil { result.name = refCommon.name }
        if refCommon.x != nil { result.x = refCommon.x }
        if refCommon.y != nil { result.y = refCommon.y }
        if refCommon.rotation != nil { result.rotation = refCommon.rotation }
        if refCommon.opacity != nil { result.opacity = refCommon.opacity }
        if refCommon.enabled != nil { result.enabled = refCommon.enabled }
        if refCommon.flipX != nil { result.flipX = refCommon.flipX }
        if refCommon.flipY != nil { result.flipY = refCommon.flipY }
        if refCommon.theme != nil { result.theme = refCommon.theme }
        // Don't transfer reusable — the expanded node is not reusable
        result.reusable = nil
        return result
    }

    // MARK: - ID Prefixing

    /// Prefixes all IDs in the node tree with the given prefix.
    static func prefixIDs(in node: PenNode, prefix: String) -> PenNode {
        PenTreeRewrite.rewrite(node, context: ()) { current, _ in
            .descend(PenNode(id: "\(prefix)/\(current.id)", common: current.common, kind: current.kind, extras: current.extras), ())
        } ?? node
    }
}
