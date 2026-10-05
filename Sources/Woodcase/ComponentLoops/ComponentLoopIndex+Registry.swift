//
//  ComponentLoopIndex+Registry.swift
//  Woodcase
//

import Foundation

extension ComponentLoopIndex {
    /// Finds the loops of a registry of whole components, as ``PenRefExpander`` holds
    /// them.
    ///
    /// - Parameter registry: Component id → the component with its subtree.
    init(registry: [String: PenNode]) {
        self.init(edges: registry.mapValues(Self.renderedInSubtree(of:)))
    }

    /// Every component id rendered anywhere in a subtree, unfiltered and possibly
    /// repeated.
    ///
    /// - Parameter root: The subtree, with its inline children.
    /// - Returns: The ids.
    static func renderedInSubtree(of root: PenNode) -> [String] {
        var rendered: [String] = []
        var pending = [root]
        while let node = pending.popLast() {
            rendered += node.renderedComponentIDs
            pending += node.kind.inlineChildren
        }
        return rendered
    }
}
