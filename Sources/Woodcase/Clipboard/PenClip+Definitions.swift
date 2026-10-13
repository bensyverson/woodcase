//
//  PenClip+Definitions.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// The component definitions the copied subtrees need, outermost first.
    ///
    /// The closure follows every component a subtree renders
    /// (``ComponentLoopIndex/renderedInSubtree(of:)``: an instance's component, one an
    /// override repoints to, an instance written as slot content), then every component
    /// those render, through the document's own components and its imported ones alike
    /// (``EditableDocument/materializedComponents()``). A ref chain is followed because
    /// a component that is a `ref` renders the component it names.
    ///
    /// A needed component is carried as its own root only when nothing already carries
    /// it: not a copied subtree, and not another needed component it is defined inside.
    /// Each is copied exactly as stored, so a paste can compare it with the target's.
    ///
    /// - Parameters:
    ///   - content: The copied subtrees.
    ///   - document: The source document.
    ///   - position: Each stored id's index in document order.
    /// - Returns: The definitions: the document's own in document order, then the
    ///   imported ones by id.
    static func definitions(
        for content: [PenNode],
        in document: EditableDocument,
        position: [String: Int]
    ) -> [PenNode] {
        let registry = document.materializedComponents()
        var needed: Set<String> = []
        var pending = content.flatMap(ComponentLoopIndex.renderedInSubtree(of:))
        while let id = pending.popLast() {
            guard let component = registry[id], needed.insert(id).inserted else { continue }
            pending += ComponentLoopIndex.renderedInSubtree(of: component)
        }

        let carried = Set(content.flatMap(subtreeIDs(of:)))
        let outermost = needed.filter { id in
            !carried.contains(id)
                && document.componentAncestors(of: id).allSatisfy { !needed.contains($0) && !carried.contains($0) }
        }
        return outermost
            .sorted { (position[$0] ?? Int.max, $0) < (position[$1] ?? Int.max, $1) }
            .compactMap { registry[$0] }
    }

    /// Every id in a subtree.
    ///
    /// - Parameter root: The subtree.
    /// - Returns: The ids, in pre-order.
    static func subtreeIDs(of root: PenNode) -> [String] {
        var ids: [String] = []
        var pending = [root]
        while let node = pending.popLast() {
            ids.append(node.id)
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return ids
    }
}
