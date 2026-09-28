//
//  EditableDocument+Expansion.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The expansion cache, lazily initialized on first expansion call.
    ///
    /// Can be `nil` for headless sync scenarios where expansion is unnecessary.
    internal(set) var expansionCache: ExpansionCache? {
        get { _expansionCache }
        set { _expansionCache = newValue }
    }

    /// Expands a single `ref` node, returning the expanded subtree with provenance.
    ///
    /// The expansion itself is ``PenRefExpander``'s, over a registry of *every*
    /// reusable in the document — so a ref nested inside the component being
    /// expanded resolves too, and a component that is itself a ref to another
    /// follows its chain.
    ///
    /// Results are cached — subsequent calls with the same `nodeID` return the
    /// cached result until the ref or its component is modified.
    ///
    /// - Parameter nodeID: The ID of the `ref` node to expand.
    /// - Returns: The expanded result with provenance information. A ref whose
    ///   component is not in the document comes back unexpanded, with provenance.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the node doesn't exist,
    ///   or ``EditingError/notARefNode(id:)`` if the node is not a `ref`.
    func expandRef(nodeID: String) throws -> ExpandedRef {
        guard let node = nodes[nodeID] else {
            throw EditingError.nodeNotFound(id: nodeID)
        }

        guard case let .ref(refData) = node.kind else {
            throw EditingError.notARefNode(id: nodeID)
        }

        if _expansionCache == nil {
            _expansionCache = ExpansionCache()
        }
        if let cached = _expansionCache?.entries[nodeID] {
            return cached
        }

        let expanded = PenRefExpander.expandRef(
            refNode: node,
            registry: materializedComponents(),
            visited: []
        )
        let result = ExpandedRef(expandedNode: expanded, provenance: provenance(of: node, refData: refData))
        _expansionCache?.store(result, for: nodeID)
        return result
    }

    /// Expands all `ref` nodes within a subtree.
    ///
    /// Materializes the subtree rooted at `rootID`, then hands it to
    /// ``PenRefExpander`` with the document's components, collecting provenance
    /// for each ref it contained.
    ///
    /// - Parameter rootID: The ID of the subtree root.
    /// - Returns: A tuple of the expanded subtree and provenance context.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the root doesn't exist.
    func expandSubtree(rootID: String) throws -> (PenNode, ExpansionContext) {
        let subtree = try materializeSubtree(rootID: rootID)
        var context = ExpansionContext()
        collectProvenance(in: subtree, into: &context)
        return (PenRefExpander.expand(subtree, registry: materializedComponents()), context)
    }

    /// Returns a fully expanded document with provenance context.
    ///
    /// This is ``expanded(for:)`` for ``PenRefExpander/Purpose/export`` — imported
    /// instances included — with provenance collected for every ref the document held.
    ///
    /// - Returns: A tuple of the expanded document and provenance context.
    func expandedDocument() -> (PenDocument, ExpansionContext) {
        let doc = materialize()
        var context = ExpansionContext()
        for child in doc.children {
            collectProvenance(in: child, into: &context)
        }
        return (expanded(for: .export), context)
    }
}

// MARK: - Private Helpers

extension EditableDocument {
    /// Every reusable component in the document, materialized with its children.
    ///
    /// ``componentRegistry`` holds the flat store's copies, whose children were
    /// stripped on the way in, so it cannot be handed to ``PenRefExpander`` as it
    /// stands — a component would expand to an empty shell. Rebuilding each one
    /// from the flat store gives the expander the registry
    /// ``PenRefExpander/buildRegistry(from:)`` would have built from the file, so
    /// the editing layer and the file pipeline expand a document identically.
    ///
    /// The components the document's imports define join them — the registry
    /// ``expanded(for:)`` hands the expander — with the document's own winning on an
    /// id both hold.
    ///
    /// - Returns: Component ID → the component's full subtree.
    func materializedComponents() -> [String: PenNode] {
        componentRegistry
            .compactMapValues { try? materializeSubtree(rootID: $0.id) }
            .merging(importedStore.expansionRegistry) { own, _ in own }
    }

    /// Records the provenance of every `ref` node in a subtree, as it is written.
    ///
    /// Provenance is a property of the ref node — which component, which overrides —
    /// so it is read from the tree *before* expansion. A ref nested inside a
    /// component is recorded only when the component definition itself is in the
    /// walk, never through the instances that expand it.
    ///
    /// - Parameters:
    ///   - node: The subtree to walk.
    ///   - context: The context to record into.
    func collectProvenance(in node: PenNode, into context: inout ExpansionContext) {
        if case let .ref(refData) = node.kind {
            context.provenance[node.id] = provenance(of: node, refData: refData)
            return
        }
        for child in node.kind.inlineChildren {
            collectProvenance(in: child, into: &context)
        }
    }

    /// The provenance of one ref node.
    ///
    /// - Parameters:
    ///   - node: The ref node.
    ///   - refData: Its ref payload, already unwrapped by the caller.
    /// - Returns: What component it instantiates, and with which overrides.
    func provenance(of node: PenNode, refData: PenNode.RefData) -> ComponentProvenance {
        ComponentProvenance(
            componentID: refData.ref,
            instanceRefID: node.id,
            appliedOverrides: refData.descendants ?? [:],
            rootOverrides: refData.rootOverrides
        )
    }
}
