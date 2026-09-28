//
//  TreeView+Expansion.swift
//  Woodcase
//

import Foundation

/// How the walk decides what an instance row stands in for — the same way the
/// expansion does.
///
/// The rows of an expanded read are only right if they are the nodes
/// ``PenRefExpander`` made, and the expander carries two things down its walk: the
/// payload of the instance each node sits directly inside, which may repoint a nested
/// `ref`, and the components already on the chain, where it stops. A walk that re-derives
/// the first at every node pays for the whole chain again at each row; one that lacks
/// the second never ends on a component that places itself — a document one `moveNode`
/// away from any component with an instance on the canvas.
extension TreeView {
    /// What the walk carries down from the instances a node sits inside.
    struct InstanceScope {
        /// The settled `ref` payload of the instance the node sits directly inside, or
        /// `nil` in the document's own tree.
        var payload: PenNode.RefData?

        /// The component ids on the expansion chain: every component an enclosing
        /// instance placed, alias links included. A `ref` naming one is circular.
        var components: Set<String>

        /// The scope of the document's own tree, inside no instance.
        static let document = InstanceScope(payload: nil, components: [])
    }

    /// What one row's node stands in for in the expansion.
    enum Placement {
        /// The node stands for itself: it is no `ref`, or one that names no reusable
        /// component, which the expansion leaves as written.
        case own

        /// A `ref` naming a component already on the chain. The expansion leaves it as
        /// written, and nothing is below it.
        case circular

        /// An instance: the component root it clones, and the scope its children sit in.
        case instance(rootID: String, scope: InstanceScope)

        /// The cloned component root, for an instance.
        var componentRootID: String? {
            if case let .instance(rootID, _) = self { rootID } else { nil }
        }
    }

    /// What a node stands in for, inside the given scope.
    ///
    /// A stored `ref` is settled against the enclosing instance's payload, which may
    /// repoint it. An injected `ref` is read from its own payload: it is in no store, and
    /// nothing can have repointed it — the instance that wrote it *is* the override.
    ///
    /// - Parameters:
    ///   - source: The row's node.
    ///   - scope: The instances it sits inside.
    ///   - document: The document, for its store and component registry.
    /// - Returns: The node's placement.
    static func placement(
        of source: Source,
        in scope: InstanceScope,
        document: EditableDocument
    ) -> Placement {
        let payload: PenNode.RefData? = switch source {
        case let .stored(id):
            document.effectiveRefData(of: id, enclosedBy: scope.payload)
        case let .injected(node):
            if case let .ref(data) = node.kind { data } else { nil }
        }
        guard let payload else { return .own }
        if scope.components.contains(payload.ref) { return .circular }
        guard let placed = document.componentPlacement(of: payload, onChain: scope.components) else { return .own }
        return .instance(rootID: placed.rootID, scope: InstanceScope(payload: payload, components: placed.chain))
    }

    /// The scope inside an instance chain, for a read that starts partway down one.
    ///
    /// Each element is settled against the one before it, as the walk would have from
    /// the top. An element the store does not hold is one an enclosing instance injected.
    ///
    /// - Parameters:
    ///   - chain: The `ref` node ids, outermost first.
    ///   - document: The document.
    /// - Returns: The scope a node directly inside the chain's innermost instance sits in.
    static func scope(insideInstances chain: [String], document: EditableDocument) -> InstanceScope {
        var scope = InstanceScope.document
        for (index, id) in chain.enumerated() {
            var source = Source.stored(id)
            if document.effectiveRefData(of: id, enclosedBy: scope.payload) == nil,
               let injected = document.injectedNodes(insideInstances: Array(chain[..<index]))[id]
            {
                source = .injected(injected.node)
            }
            guard case let .instance(_, inner) = placement(of: source, in: scope, document: document)
            else { break }
            scope = inner
        }
        return scope
    }
}
