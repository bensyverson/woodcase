//
//  TreeMoveCRDT+Cycles.swift
//  Woodcase
//

import Foundation

extension TreeMoveCRDT {
    /// A node on a parent cycle in the current or the initial parent map, or `nil` when
    /// both are forests.
    ///
    /// ``applyMove(_:)`` keeps a tree it built acyclic, but a decoded one — a snapshot
    /// from another peer — can hold anything, and ``wouldCreateCycle(nodeID:newParentID:)``
    /// would walk a cycle forever. Each map is checked in time linear in its size.
    func firstCycleNode() -> String? {
        Self.firstCycleNode(in: parentMap) ?? Self.firstCycleNode(in: initialParentMap)
    }

    /// A node on a parent cycle in `map`, or `nil` when it has none.
    private static func firstCycleNode(in map: [String: String?]) -> String? {
        var settled = Set<String>()
        for start in map.keys.sorted() where !settled.contains(start) {
            var path: [String] = []
            var onPath = Set<String>()
            var current: String? = start
            while let node = current, !settled.contains(node) {
                guard onPath.insert(node).inserted else { return node }
                path.append(node)
                current = map[node] ?? nil
            }
            settled.formUnion(path)
        }
        return nil
    }
}
