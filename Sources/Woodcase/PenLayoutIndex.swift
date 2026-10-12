//
//  PenLayoutIndex.swift
//  Woodcase
//

import Foundation

/// Where each node of an expanded document sits: its parent, its place among its
/// siblings, its depth and its root, keyed by its post-expansion id.
///
/// The layout engine walks a ``PenDocument`` whose nodes hold their children inline, so
/// finding a node's root or ancestors means a walk from the top. This index answers those
/// in a lookup, and it is what translates a source dirty set into the expanded ids layout
/// must redo: ``expandedIDs(for:)``.
///
/// ## Instance roots
///
/// ``PenRefExpander`` prefixes every id inside an instance with its ref's id, so the
/// nodes of the instance placed by `R5` answer to `R5/…`. An **instance root** of a ref
/// is a node whose id starts `<ref>/` and whose parent's does not — the root of the clone,
/// `R5/Card`. Nested instances share the outer prefix (`b3Panel/panelCard/Card`), so they
/// are not roots of their own outer ref. A `ref` left standing by the expander — its
/// component missing — keeps its own id and is found as itself.
///
/// ## Duplicate ids
///
/// Two nodes under one id (an authored `Inst1/Card1` beside the expansion of `Inst1`)
/// cannot both own an entry, exactly as they cannot both own a rect. The first in
/// pre-order keeps the entry; the children of both are listed under the id, so a
/// translation dirties the union — more than it must, never less.
public struct PenLayoutIndex: Friendly {
    /// One node's place in the expanded tree.
    public struct Entry: Friendly {
        /// The parent's expanded id, `nil` for a top-level node.
        public let parent: String?

        /// The node's index among its parent's children — among the top-level nodes for
        /// a top-level one.
        public let index: Int

        /// How many ancestors the node has: `0` at the top level.
        public let depth: Int

        /// The expanded id of the top-level node holding it, its own at the top level.
        public let root: String

        /// An entry.
        ///
        /// - Parameters:
        ///   - parent: The parent's expanded id, `nil` at the top level.
        ///   - index: The index among the parent's children.
        ///   - depth: The number of ancestors.
        ///   - root: The top-level node holding it.
        public init(parent: String?, index: Int, depth: Int, root: String) {
            self.parent = parent
            self.index = index
            self.depth = depth
            self.root = root
        }
    }

    /// The top-level nodes' expanded ids, in document order.
    public private(set) var roots: [String] = []

    /// Every node's entry.
    var entries: [String: Entry] = [:]

    /// Every container's children, in order.
    var childLists: [String: [String]] = [:]

    /// The instance roots of each ref, by the ref's id.
    var instanceRootLists: [String: [String]] = [:]

    /// Indexes an expanded document.
    ///
    /// - Parameter document: A ref-expanded document, as the layout engine reads it.
    public init(_ document: PenDocument) {
        // Pre-order from a work list, not recursion, so a deep tree cannot overflow a
        // Swift task's stack in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        var pending: [(node: PenNode, entry: Entry)] = document.children.enumerated().reversed().map { index, node in
            (node, Entry(parent: nil, index: index, depth: 0, root: node.id))
        }
        while let (node, entry) = pending.popLast() {
            if let parent = entry.parent {
                childLists[parent, default: []].append(node.id)
            } else {
                roots.append(node.id)
            }
            if entries[node.id] == nil {
                entries[node.id] = entry
            }
            if let ref = Self.instancePrefix(of: node.id), ref != entry.parent.flatMap(Self.instancePrefix(of:)) {
                instanceRootLists[ref, default: []].append(node.id)
            }
            let children = PenLayoutEngine.nodeChildren(node) ?? []
            for (index, child) in children.enumerated().reversed() {
                pending.append((child, Entry(parent: node.id, index: index, depth: entry.depth + 1, root: entry.root)))
            }
        }
    }

    /// The id of the outermost ref an expanded id was cloned under: the part before its
    /// first `/`, or `nil` for an id with none.
    ///
    /// - Parameter id: An expanded id.
    /// - Returns: The ref's id.
    static func instancePrefix(of id: String) -> String? {
        id.firstIndex(of: "/").map { String(id[..<$0]) }
    }

    /// The number of nodes indexed.
    public var count: Int {
        entries.count
    }

    /// A node's entry, or `nil` when the document holds no node under the id.
    ///
    /// - Parameter id: The node's expanded id.
    public subscript(_ id: String) -> Entry? {
        entries[id]
    }

    /// A node's children, in order; empty for a leaf or an id the index does not hold.
    ///
    /// - Parameter id: The node's expanded id.
    /// - Returns: The children's expanded ids.
    public func children(of id: String) -> [String] {
        childLists[id] ?? []
    }

    /// A node's ancestors, nearest first.
    ///
    /// - Parameter id: The node's expanded id.
    /// - Returns: Its parent, its parent's parent and so on up to its root; empty for a
    ///   top-level node or an id the index does not hold.
    public func ancestors(of id: String) -> [String] {
        var result: [String] = []
        var current = entries[id]?.parent
        while let parent = current {
            result.append(parent)
            current = entries[parent]?.parent
        }
        return result
    }

    /// A node and every node under it, in pre-order.
    ///
    /// - Parameter id: The node's expanded id.
    /// - Returns: The subtree's expanded ids, empty when the index does not hold the id.
    public func subtree(of id: String) -> [String] {
        guard entries[id] != nil else { return [] }
        var result: [String] = []
        var visited: Set<String> = []
        var pending = [id]
        while let next = pending.popLast() {
            // A duplicated id lists the children of both its nodes; visit each id once.
            guard visited.insert(next).inserted else { continue }
            result.append(next)
            pending.append(contentsOf: children(of: next).reversed())
        }
        return result
    }

    /// The roots of the instances a ref placed.
    ///
    /// - Parameter refID: The `ref` node's id.
    /// - Returns: The expanded ids of its instance roots — usually one — in document order.
    public func instanceRoots(of refID: String) -> [String] {
        instanceRootLists[refID] ?? []
    }
}
