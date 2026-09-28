//
//  ComponentProvenance.swift
//  Woodcase
//

import Foundation

/// Tracks the origin of an expanded component instance.
///
/// When a `ref` node is expanded, ``ComponentProvenance`` records which component
/// was instantiated, which ref node triggered the expansion, and what overrides
/// were applied. This enables editor UIs to show component relationships and
/// override state for expanded nodes.
public struct ComponentProvenance: Friendly {
    /// The ID of the reusable component definition.
    public var componentID: String

    /// The ID of the `ref` node that was expanded.
    public var instanceRefID: String

    /// Descendant overrides that were applied during expansion.
    public var appliedOverrides: [String: PenDescendantOverride]

    /// Root overrides that were applied to the component's root node.
    public var rootOverrides: [String: AnyCodable]?

    public init(
        componentID: String,
        instanceRefID: String,
        appliedOverrides: [String: PenDescendantOverride] = [:],
        rootOverrides: [String: AnyCodable]? = nil
    ) {
        self.componentID = componentID
        self.instanceRefID = instanceRefID
        self.appliedOverrides = appliedOverrides
        self.rootOverrides = rootOverrides
    }
}

/// The result of expanding a single `ref` node.
///
/// Contains both the expanded node tree (with prefixed IDs) and the
/// provenance information tracking the expansion's origin.
public struct ExpandedRef: Friendly {
    /// The expanded subtree with prefixed IDs.
    public var expandedNode: PenNode

    /// Provenance tracking the component and overrides used.
    public var provenance: ComponentProvenance

    public init(expandedNode: PenNode, provenance: ComponentProvenance) {
        self.expandedNode = expandedNode
        self.provenance = provenance
    }
}

/// Collected provenance information for a multi-ref expansion.
///
/// Used by ``EditableDocument/expandSubtree(rootID:)`` and
/// ``EditableDocument/expandedDocument()`` to report all component
/// instances found during expansion.
public struct ExpansionContext: Friendly {
    /// Provenance for each expanded ref, keyed by the original ref node ID.
    public var provenance: [String: ComponentProvenance]

    public init(provenance: [String: ComponentProvenance] = [:]) {
        self.provenance = provenance
    }
}
