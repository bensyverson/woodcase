//
//  ComponentRenderGraph.swift
//  Woodcase
//

import Foundation

/// Which components render which, as far as one component reaches, split into the
/// groups that render each other.
///
/// A vertex is a node some `ref` renders; its edges go to every component rendered
/// anywhere in its subtree (``EditableDocument/componentsRendered(by:)`` of each node in
/// it). A group — a strongly connected component — is *cyclic* when it holds more than
/// one vertex, or one that renders itself. ``EditableDocument/revision(of:)`` gives every
/// cyclic group one shared revision, because none of its members can be hashed before
/// the others.
///
/// Groups come out in reverse topological order — a group before any group that renders
/// it — which is the order their revisions have to be computed in. Tarjan's algorithm,
/// run from a work list rather than by recursion, so a long chain of components cannot
/// overflow a task's stack.
struct ComponentRenderGraph: Friendly {
    /// The components each vertex renders, sorted.
    let edges: [String: [String]]

    /// Builds the graph reachable from one component.
    ///
    /// - Parameters:
    ///   - start: The component to start from.
    ///   - rendered: The components rendered in a vertex's subtree; a vertex whose
    ///     group is already known passes none, which makes it a sink.
    init(from start: String, rendered: (String) -> [String]) {
        var edges: [String: [String]] = [:]
        var pending = [start]
        while let vertex = pending.popLast() {
            guard edges[vertex] == nil else { continue }
            let targets = Array(Set(rendered(vertex))).sorted()
            edges[vertex] = targets
            pending.append(contentsOf: targets.filter { edges[$0] == nil })
        }
        self.edges = edges
    }

    /// The cyclic groups, each sorted, in reverse topological order.
    var cyclicGroups: [[String]] {
        groups.filter { group in
            group.count > 1 || (edges[group[0]] ?? []).contains(group[0])
        }
    }

    /// Every group, each sorted, in reverse topological order.
    var groups: [[String]] {
        var index: [String: Int] = [:]
        var lowlink: [String: Int] = [:]
        var onStack: Set<String> = []
        var stack: [String] = []
        var result: [[String]] = []
        var counter = 0

        for root in edges.keys.sorted() where index[root] == nil {
            // Each frame is a vertex and the position of its next edge to explore.
            var frames: [(vertex: String, next: Int)] = [(root, 0)]
            index[root] = counter
            lowlink[root] = counter
            counter += 1
            stack.append(root)
            onStack.insert(root)

            while let last = frames.indices.last {
                let vertex = frames[last].vertex
                let targets = edges[vertex] ?? []
                if frames[last].next < targets.count {
                    let target = targets[frames[last].next]
                    frames[last].next += 1
                    if index[target] == nil {
                        index[target] = counter
                        lowlink[target] = counter
                        counter += 1
                        stack.append(target)
                        onStack.insert(target)
                        frames.append((target, 0))
                    } else if onStack.contains(target) {
                        lowlink[vertex] = min(lowlink[vertex, default: 0], index[target, default: 0])
                    }
                    continue
                }
                frames.removeLast()
                if let parent = frames.last?.vertex {
                    lowlink[parent] = min(lowlink[parent, default: 0], lowlink[vertex, default: 0])
                }
                guard lowlink[vertex] == index[vertex] else { continue }
                var group: [String] = []
                while let member = stack.popLast() {
                    onStack.remove(member)
                    group.append(member)
                    if member == vertex { break }
                }
                result.append(group.sorted())
            }
        }
        return result
    }
}
