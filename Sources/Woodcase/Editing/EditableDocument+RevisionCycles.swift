//
//  EditableDocument+RevisionCycles.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Works out the shared revision of every cyclic group a component reaches, and
    /// memoizes each member's in ``RevisionCache/cycles``.
    ///
    /// Groups are resolved in reverse topological order, so when a group's members are
    /// hashed every group they render is known already, and only references to the
    /// group itself are written as markers. For a group *G* with members *m₁ … mₙ* in
    /// id order:
    ///
    /// - each member's working hash is its fold with every reference to a member of *G*
    ///   folded in as ``cycleMarker(_:)``;
    /// - *G*'s revision is FNV-1a over `cycle`, then each member's id and working hash;
    /// - a reference to member *m* folds in FNV-1a over *G*'s revision and *m*'s id.
    ///
    /// Each value reads only the document, never the walk that found the cycle, so it
    /// is the same whichever node was asked for first and in whichever process.
    ///
    /// - Parameter component: A component the fold met on its own chain.
    func resolveComponentCycles(reachableFrom component: String) {
        if _revisionCache == nil {
            _revisionCache = RevisionCache()
        }
        let graph = ComponentRenderGraph(from: component) { vertex in
            // A vertex whose group is known already renders nothing new.
            _revisionCache?.cycles[vertex] == nil ? componentsRendered(inSubtreeOf: vertex) : []
        }
        var groups = graph.cyclicGroups
        // The fold only reports a component on its own chain, which is always in a
        // cyclic group; this keeps the fold's retry total even if that ever failed.
        if !groups.contains(where: { $0.contains(component) }) {
            groups.append([component])
        }
        for group in groups {
            let members = Set(group)
            var hasher = FNV1aHasher()
            hasher.combine("cycle")
            for member in group {
                hasher.combine(member)
                if case let .revision(working?) = fold(member, markers: members) {
                    hasher.combine(working)
                }
            }
            let groupRevision = hasher.hexString
            for member in group {
                var memberHasher = FNV1aHasher()
                memberHasher.combine(groupRevision)
                memberHasher.combine(member)
                _revisionCache?.storeCycle(memberHasher.hexString, for: member)
            }
        }
    }

    /// Every component rendered by a node or anything under it, existing ones only.
    ///
    /// - Parameter rootID: The subtree's root.
    /// - Returns: The component ids, unordered and possibly repeated.
    private func componentsRendered(inSubtreeOf rootID: String) -> [String] {
        var rendered: [String] = []
        var pending = [rootID]
        while let id = pending.popLast() {
            guard let node = nodes[id] else { continue }
            rendered += componentsRendered(by: node).filter { nodes[$0] != nil }
            pending += children[id] ?? []
        }
        return rendered
    }
}
