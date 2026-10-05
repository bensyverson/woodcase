//
//  ComponentGraphSite.swift
//  Woodcase
//

import Foundation

/// What one node contributes to the component graph, read at one moment.
///
/// The graph ``ComponentLoopIndex`` finds loops in has a vertex per component and an edge
/// for each id a node inside it renders. A node can change that only by being a
/// component, by rendering something while inside one, or by carrying such nodes into or
/// out of one — so reading these few facts before and after an edit tells whether the
/// memoized loops still stand (``EditableDocument/invalidatesComponentLoops(_:before:after:)``).
struct ComponentGraphSite: Friendly {
    /// The node's parent, `nil` at the root or for a node not in the document.
    var parent: String?

    /// Whether the node is a reusable component.
    var isComponent: Bool

    /// Whether some ancestor of the node is a reusable component.
    var isInsideComponent: Bool

    /// The ids the node renders (``PenNode/renderedComponentIDs``).
    var rendered: [String]
}
