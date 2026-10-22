//
//  PenNode+Flatten.swift
//  WoodcaseBench
//

import Woodcase

extension PenNode {
    /// Every node under `roots`, depth first, parents before children — a work-list
    /// walk, so a deep fixture cannot overflow the stack.
    ///
    /// - Parameter roots: The trees.
    /// - Returns: Their nodes.
    static func flatten(_ roots: [PenNode]) -> [PenNode] {
        var nodes: [PenNode] = []
        var pending = Array(roots.reversed())
        while let node = pending.popLast() {
            nodes.append(node)
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return nodes
    }
}
