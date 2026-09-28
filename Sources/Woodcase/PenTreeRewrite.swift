//
//  PenTreeRewrite.swift
//  Woodcase
//

import Foundation

/// Rewrites a tree of inline ``PenNode``s top-down, without recursion.
///
/// Every walk the expansion makes — expanding refs, patching overrides, prefixing ids,
/// stripping definitions — rebuilds the tree it walks. Written recursively, each level
/// of the tree cost a few stack frames, and a debug build gives every `PenNode`
/// temporary in those frames its own slot: an expansion used kilobytes of stack per
/// level and overflowed a Swift task's 512 KiB four nested instances deep. This walk
/// keeps its pending work in an array on the heap instead, so its stack use does not
/// grow with the tree. See `project/2026-09-26-debug-stack-depth.md`.
///
/// The visitor sees each node — children still attached — before anything below it,
/// with the context its parent handed down, and answers with a ``Step``.
enum PenTreeRewrite {
    /// What to do with the node just visited.
    enum Step<Context> {
        /// Keep this node, then visit its children with the given context. The node's
        /// own children are the ones visited, so a visitor that replaced them has its
        /// replacement walked.
        case descend(PenNode, Context)

        /// Keep this node as it is; nothing below it is visited.
        case keep(PenNode)

        /// Leave the node out.
        case drop
    }

    /// Rewrites a list of sibling trees.
    ///
    /// - Parameters:
    ///   - roots: The trees, in order.
    ///   - context: The context the roots are visited with.
    ///   - visit: Decides each node's fate.
    /// - Returns: The rewritten trees, in order. A container whose `children` is `nil`
    ///   keeps `nil`; one whose children were all dropped gets an empty list.
    static func rewrite<Context>(
        _ roots: [PenNode],
        context: Context,
        visit: (PenNode, Context) -> Step<Context>
    ) -> [PenNode] {
        var stack = [Level(node: nil, pending: roots, context: context)]
        while let last = stack.indices.last {
            guard stack[last].next < stack[last].pending.count else {
                let finished = stack.removeLast()
                guard var node = finished.node else { return finished.built }
                node.kind = node.kind.replacingInlineChildren(with: finished.built)
                stack[stack.count - 1].built.append(node)
                continue
            }
            let child = stack[last].pending[stack[last].next]
            stack[last].next += 1

            switch visit(child, stack[last].context) {
            case .drop:
                continue
            case let .keep(node):
                stack[last].built.append(node)
            case let .descend(node, childContext):
                let children = node.kind.inlineChildrenIfPresent
                guard let children, !children.isEmpty else {
                    stack[last].built.append(node)
                    continue
                }
                stack.append(Level(node: node, pending: children, context: childContext))
            }
        }
        return []
    }

    /// Rewrites one tree.
    ///
    /// - Parameters:
    ///   - root: The tree.
    ///   - context: The context the root is visited with.
    ///   - visit: Decides each node's fate.
    /// - Returns: The rewritten tree, or `nil` when the root was dropped.
    static func rewrite<Context>(
        _ root: PenNode,
        context: Context,
        visit: (PenNode, Context) -> Step<Context>
    ) -> PenNode? {
        rewrite([root], context: context, visit: visit).first
    }

    /// One container whose children are being walked.
    private struct Level<Context> {
        /// The container, or `nil` for the list of roots.
        var node: PenNode?

        /// Its children as they were when the walk reached them.
        var pending: [PenNode]

        /// The context its children are visited with.
        var context: Context

        /// The index of the next child to visit.
        var next = 0

        /// The children rewritten so far.
        var built: [PenNode] = []
    }
}
