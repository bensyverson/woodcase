//
//  PenOverrideKeyResolver+Builder.swift
//  Woodcase
//

import Foundation

extension PenOverrideKeyResolver {
    /// Children a `descendants` entry writes into a node, and the scope that wrote them.
    struct Fill: Friendly {
        /// The nodes, as written.
        var children: [PenNode]

        /// The scope whose JSON holds the entry.
        var writer: Int
    }

    /// Walks a component the way ``PenRefExpander`` expands it, recording each node's
    /// path and who wrote it, without building the expansion itself.
    struct Builder: Friendly {
        /// Component id → component.
        let registry: [String: PenNode]

        /// The nodes placed so far, in pre-order.
        var entries: [Entry] = []

        /// The next unused scope number.
        private var nextScope = PenOverrideKeyResolver.componentScope + 1

        /// Creates a builder over a registry.
        ///
        /// - Parameter registry: Component id → component.
        init(registry: [String: PenNode]) {
            self.registry = registry
        }

        /// One node still to place, or one whose subtree has just been placed.
        private enum Work: Friendly {
            /// Place this node and queue what the expansion puts below it.
            case place(PenNode, Placement)

            /// The subtree of the entry at this index is complete.
            case close(Int)
        }

        /// Where a node is placed, and what reaches it from above.
        private struct Placement: Friendly {
            /// The instance ids down to the node, each followed by `/`.
            var prefix: String

            /// The scope that wrote the node.
            var writer: Int

            /// The scope whose expansion the node sits in.
            var placement: Int

            /// Slot fills reaching this placement, keyed by path within it.
            var fills: [String: Fill]

            /// The component ids on this chain, so a cycle stops.
            var visited: Set<String>
        }

        /// Places a component root and its tree, as the component itself wrote them.
        ///
        /// The walk keeps its pending nodes in an array rather than on the call stack:
        /// it follows every nested instance to the bottom, so it is as deep as the whole
        /// expansion, and a debug build's frames would overflow a task's stack.
        ///
        /// - Parameter component: The component root, with its children.
        mutating func placeRoot(_ component: PenNode) {
            let scope = PenOverrideKeyResolver.componentScope
            let root = append(component, path: component.id, writer: scope, placement: scope)
            let placement = Placement(prefix: "", writer: scope, placement: scope, fills: [:], visited: [component.id])
            var work: [Work] = [.close(root)]
            work += component.kind.inlineChildren.reversed().map { .place($0, placement) }
            while let next = work.popLast() {
                switch next {
                case let .close(index):
                    entries[index].end = entries.count
                case let .place(node, placement):
                    let index = append(
                        node, path: placement.prefix + node.id,
                        writer: placement.writer, placement: placement.placement
                    )
                    work.append(.close(index))
                    work += below(node, at: index, placement).reversed().map { .place($0.node, $0.placement) }
                }
            }
        }

        /// The nodes the expansion puts directly below one placed node.
        ///
        /// For an instance, those are the children of the component it clones, with
        /// the slots it and any outer instance fill; the instance's own `descendants`
        /// — and `children` written on the `ref` node, which fill its component's root —
        /// are slot content written by the instance's writer, and a fill reaching it
        /// from outside (`id/…`) wins over one it writes, as the expander applies the
        /// outer key after the inner one. For any other node, its fill or its children.
        private mutating func below(
            _ node: PenNode,
            at index: Int,
            _ placement: Placement
        ) -> [(node: PenNode, placement: Placement)] {
            guard case let .ref(data) = node.kind else {
                let fill = placement.fills[node.id]
                var inner = placement
                inner.writer = fill?.writer ?? placement.writer
                return (fill?.children ?? node.kind.inlineChildren).map { ($0, inner) }
            }
            guard let component = component(named: data.ref, visited: placement.visited) else { return [] }
            let scope = nextScope
            nextScope += 1
            entries[index].enters = scope

            var inner: [String: Fill] = [:]
            for (key, override) in data.descendants ?? [:] {
                if let children = Self.children(of: override) {
                    inner[key] = Fill(children: children, writer: placement.writer)
                }
            }
            let marker = node.id + "/"
            for (key, fill) in placement.fills where key.hasPrefix(marker) {
                inner[String(key.dropFirst(marker.count))] = fill
            }

            // The root's children can be replaced three ways, in the order the expander
            // lets each win: an entry keyed by the root's own id, then `children` an
            // outer override writes onto the ref node, then the ref node's own.
            let fill = inner[component.id]
                ?? placement.fills[node.id]
                ?? data.rootOverrides?[PenNodePatcher.childrenKey].flatMap(Self.nodes(in:))
                .map { Fill(children: $0, writer: placement.writer) }
            let entered = Placement(
                prefix: placement.prefix + marker, writer: fill?.writer ?? scope, placement: scope,
                fills: inner, visited: placement.visited.union([component.id])
            )
            return (fill?.children ?? component.kind.inlineChildren).map { ($0, entered) }
        }

        /// The component a `ref` clones, following alias chains, or `nil` for a
        /// missing one or one already on this chain.
        private func component(named ref: String, visited: Set<String>) -> PenNode? {
            var seen = visited
            var current = ref
            while seen.insert(current).inserted, let node = registry[current] {
                guard case let .ref(inner) = node.kind else { return node }
                current = inner.ref
            }
            return nil
        }

        /// Records a node, its extent to be filled in once its subtree is placed.
        private mutating func append(_ node: PenNode, path: String, writer: Int, placement: Int) -> Int {
            entries.append(Entry(id: node.id, path: path, writer: writer, placement: placement, enters: nil, end: 0))
            return entries.count - 1
        }

        /// The `children` a `descendants` entry writes, decoded, or `nil`.
        private static func children(of override: PenDescendantOverride) -> [PenNode]? {
            override.properties[PenNodePatcher.childrenKey].flatMap(nodes(in:))
        }

        /// A `children` value decoded, or `nil` when it is not a list of nodes.
        private static func nodes(in value: AnyCodable) -> [PenNode]? {
            PenNodePatcher.decoded([PenNode].self, from: value)
        }
    }
}
