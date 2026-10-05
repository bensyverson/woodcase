//
//  ComponentLoopIndex.swift
//  Woodcase
//

import Foundation

/// The component loops of one registry, and the rule every expansion follows around
/// them.
///
/// The graph has a vertex per component and an edge from a component to every component
/// an instance anywhere in its subtree renders — ``PenNode/renderedComponentIDs``, so a
/// repointed nested ref and an instance written as slot content count. A loop is a
/// cyclic group of that graph (``ComponentRenderGraph/cyclicGroups``).
///
/// **The rule.** An instance is not expanded when its component is already on the
/// expansion chain, or when any member of its component's loop is: the nesting among a
/// loop's members is ignored. The rule depends only on the document, never on where the
/// expansion started, and it bounds every expansion — a chain holds each loop at most
/// once — where the older rule, "not a component already on the chain", let a loop of
/// *n* tangled components expand along every one of its paths: a chain of 223 components
/// each holding the next two drew a Fibonacci number of nodes.
///
/// ``PenRefExpander``, ``PenOverrideKeyResolver``, the descendant keys and the tree's
/// instance rows all ask ``closesLoop(entering:onChain:)``, so the keys, the rows and
/// the expansion agree.
struct ComponentLoopIndex: Friendly {
    /// Each component's targets that are components, sorted.
    let edges: [String: [String]]

    /// The cyclic groups, each sorted, ordered by their first member.
    let groups: [[String]]

    /// The index in ``groups`` of each component in a loop.
    let groupOf: [String: Int]

    /// An index with no components and so no loops.
    static let empty = ComponentLoopIndex(edges: [:])

    /// Finds the loops of a component graph.
    ///
    /// - Parameter edges: Each component's targets. Targets that are not keys are
    ///   ignored: they are not components.
    init(edges: [String: [String]]) {
        let components = Set(edges.keys)
        let pruned = edges.mapValues { targets in Array(Set(targets.filter(components.contains))).sorted() }
        self.edges = pruned
        let found = ComponentRenderGraph(edges: pruned).cyclicGroups.sorted { $0[0] < $1[0] }
        groups = found
        var membership: [String: Int] = [:]
        for (index, group) in found.enumerated() {
            for member in group {
                membership[member] = index
            }
        }
        groupOf = membership
    }

    /// Whether the graph holds any loop.
    var hasLoops: Bool {
        !groups.isEmpty
    }

    /// Whether an instance of `target` must stay unexpanded on this chain: the component
    /// is on it already, or a member of its loop is.
    ///
    /// - Parameters:
    ///   - target: The component an instance names.
    ///   - chain: The components already on the expansion chain.
    /// - Returns: `true` when the instance is left as written.
    func closesLoop(entering target: String, onChain chain: Set<String>) -> Bool {
        if chain.contains(target) { return true }
        guard let group = groupOf[target] else { return false }
        return chain.contains { groupOf[$0] == group }
    }

    /// The loops, named.
    ///
    /// - Parameter name: A component's display name.
    /// - Returns: One ``ComponentLoop`` per group, its cycle first.
    func loops(naming name: (String) -> String) -> [ComponentLoop] {
        groups.map { group in
            let start = group[0]
            let cycle = path(from: start, to: start, within: Set(group)) ?? [start]
            let rest = group.filter { !cycle.contains($0) }
            return ComponentLoop(
                members: (cycle + rest).map { ComponentLoop.Member(id: $0, name: name($0)) },
                cycleLength: cycle.count
            )
        }
    }

    /// The shortest walk along edges from one component to another, by breadth-first
    /// search: `from`, then each component after it, the last of which renders `to`.
    ///
    /// - Parameters:
    ///   - from: Where the walk starts.
    ///   - to: Where it must arrive. When it is `from`, the walk is a cycle.
    ///   - allowed: The components it may pass through, or `nil` for any.
    /// - Returns: The components in order, `to` left off the end; `nil` when `to` cannot
    ///   be reached.
    func path(from: String, to: String, within allowed: Set<String>? = nil) -> [String]? {
        Self.path(from: from, to: to) { vertex in
            (edges[vertex] ?? []).filter { allowed?.contains($0) ?? true }
        }
    }

    /// The shortest walk from one vertex to another over targets the caller supplies.
    ///
    /// - Parameters:
    ///   - from: Where the walk starts.
    ///   - to: Where it must arrive.
    ///   - targets: Each vertex's targets.
    /// - Returns: The vertices in order, `to` left off the end; `nil` when it cannot be
    ///   reached.
    static func path(from: String, to: String, targets: (String) -> [String]) -> [String]? {
        var previous: [String: String] = [:]
        var queue = [from]
        var head = 0
        var seen: Set<String> = []
        while head < queue.count {
            let vertex = queue[head]
            head += 1
            for target in targets(vertex) {
                if target == to {
                    var walk = [vertex]
                    var cursor = vertex
                    while cursor != from, let back = previous[cursor] {
                        walk.append(back)
                        cursor = back
                    }
                    return walk.reversed()
                }
                guard target != from, seen.insert(target).inserted else { continue }
                previous[target] = vertex
                queue.append(target)
            }
        }
        return nil
    }
}
