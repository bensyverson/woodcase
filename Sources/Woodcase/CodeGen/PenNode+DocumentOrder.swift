//
//  PenNode+DocumentOrder.swift
//  Woodcase
//

extension PenNode {
    /// `roots` and every node under them in a frame or a group, in document order — each
    /// node before its children, children in order — walked from a work list, so a deep
    /// tree costs no stack (issue `g5SACU`).
    ///
    /// Code generation's analyzers read a tree this way; an instance's children come from
    /// its component, and are not among its own.
    ///
    /// - Parameter roots: The trees, in order.
    /// - Returns: Their nodes, in document order.
    static func inDocumentOrder(_ roots: [PenNode]) -> [PenNode] {
        walk(roots) { _ in true }
    }

    /// ``inDocumentOrder(_:)`` without the nodes switched off (`enabled: false`) and
    /// everything under them: the nodes the generated code draws.
    ///
    /// - Parameter roots: The trees, in order.
    /// - Returns: Their enabled nodes, in document order.
    static func enabledInDocumentOrder(_ roots: [PenNode]) -> [PenNode] {
        walk(roots) { $0.common.enabled?.literalValue != false }
    }

    /// The nodes of `roots` that `includes` keeps, in document order, a node it refuses
    /// pruned with its subtree.
    private static func walk(_ roots: [PenNode], including includes: (PenNode) -> Bool) -> [PenNode] {
        var nodes: [PenNode] = []
        var pending = Array(roots.reversed())
        while let node = pending.popLast() {
            guard includes(node) else { continue }
            nodes.append(node)
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return nodes
    }
}
