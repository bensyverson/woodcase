//
//  PenNode+Equatable.swift
//  Woodcase
//

import Foundation

/// Comparing and hashing a node and its whole subtree from a work list.
///
/// The synthesized `==` compared a frame's children inside the frame's own comparison —
/// `PenNode ==`, `Kind ==`, `FrameData ==`, `Array ==` and the next `PenNode ==`, five
/// frames and about 68 KB of debug stack a level — so comparing two copies of an
/// eight-level mockup overflowed a Swift task's 512 KiB stack (issue `a1p6vh`). Here
/// each node is compared **shallow**, then its children are queued.
///
/// The shallow comparison leaves no field to remember: a node's `id`, `common` and
/// `extras` are compared whole, and its kind by the kind's own synthesized `==` — on the
/// kind itself when it holds no children, and on its payload with `children` taken out
/// when it does (``Kind/childlessMatch(_:_:)``). A field added to a payload is compared
/// without anyone touching this file; a stored property added to ``PenNode`` itself must
/// join ``==(_:_:)``, ``hash(into:)`` and ``customMirror``, and `PenNodeEqualityTests`
/// fails until it does.
///
/// The meaning is the synthesized one: every stored property of every node, children in
/// order and counted, a declared empty list distinct from none. Two nodes that share a
/// container's storage are equal without the subtree being walked, as `Array`'s own
/// `==` already treats two arrays sharing a buffer.
extension PenNode {
    /// Whether two nodes and everything beneath them are the same.
    ///
    /// - Parameters:
    ///   - lhs: A node.
    ///   - rhs: Another node.
    /// - Returns: `true` when every stored property of every node in the two trees is
    ///   equal, children in the same order.
    public static func == (lhs: PenNode, rhs: PenNode) -> Bool {
        var pending: [SiblingPair] = []
        guard shellsMatch(lhs, rhs, queueing: &pending) else { return false }
        while let pair = pending.popLast() {
            // Read each node where it lies: a buffer's subscript returns a copy, which
            // retains every reference the node holds; a pointer's lends the original.
            let matched = pair.lhs.withUnsafeBufferPointer { lhsBuffer in
                pair.rhs.withUnsafeBufferPointer { rhsBuffer in
                    for index in lhsBuffer.indices where !shellsMatch(lhsBuffer[index], rhsBuffer[index], queueing: &pending) {
                        return false
                    }
                    return true
                }
            }
            guard matched else { return false }
        }
        return true
    }

    /// Hashes the node and everything beneath it: each node without its children, a
    /// container's child count and whether it declares a list, then each sibling list
    /// in the order the walk takes them.
    ///
    /// - Parameter hasher: The hasher to feed.
    public func hash(into hasher: inout Hasher) {
        var pending: [[PenNode]] = []
        Self.hashShell(of: self, into: &hasher, queueing: &pending)
        while let siblings = pending.popLast() {
            siblings.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                for index in 0 ..< buffer.count {
                    Self.hashShell(of: base[index], into: &hasher, queueing: &pending)
                }
            }
        }
    }

    // MARK: - One node

    /// Two containers' children, still to compare pairwise.
    ///
    /// A struct rather than a tuple: a debug build looks a tuple type's metadata up at
    /// run time, behind a lock, every time it is made.
    struct SiblingPair {
        /// The left node's children.
        let lhs: [PenNode]

        /// The right node's children.
        let rhs: [PenNode]
    }

    /// Compares two nodes without their children, and queues the children when the rest
    /// matches and they are not already known to be equal.
    ///
    /// - Parameters:
    ///   - lhs: A node.
    ///   - rhs: Another node.
    ///   - pending: The work list the children go onto.
    /// - Returns: Whether everything but the children matches, and the children are
    ///   as many.
    private static func shellsMatch(
        _ lhs: PenNode,
        _ rhs: PenNode,
        queueing pending: inout [SiblingPair]
    ) -> Bool {
        guard lhs.id == rhs.id else { return false }
        switch lhs.storage {
        case let .leaf(lhsKind):
            // One holding children and the other none differ in their kinds.
            guard case let .leaf(rhsKind) = rhs.storage,
                  Kind.sameBox(lhsKind, rhsKind) || lhsKind == rhsKind
            else { return false }
        case let .container(lhsOwner):
            guard case let .container(rhsOwner) = rhs.storage else { return false }
            if lhsOwner !== rhsOwner {
                guard let pair = Kind.childlessMatch(lhsOwner.kind, rhsOwner.kind), pair.lhs.count == pair.rhs.count
                else { return false }
                if !sameBuffer(pair.lhs, pair.rhs) {
                    pending.append(pair)
                }
            }
        }
        return lhs.common == rhs.common && lhs.extras == rhs.extras
    }

    /// Whether two arrays share one buffer, and so hold the same nodes.
    ///
    /// The same shortcut `Array`'s own `==` takes.
    private static func sameBuffer(_ lhs: [PenNode], _ rhs: [PenNode]) -> Bool {
        lhs.withUnsafeBufferPointer { lhsBuffer in
            rhs.withUnsafeBufferPointer { $0.baseAddress == lhsBuffer.baseAddress }
        }
    }

    /// Hashes one node without its children, and queues the children.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - hasher: The hasher to feed.
    ///   - pending: The work list the children go onto.
    private static func hashShell(
        of node: PenNode,
        into hasher: inout Hasher,
        queueing pending: inout [[PenNode]]
    ) {
        hasher.combine(node.id)
        hasher.combine(node.common)
        hasher.combine(node.extras)
        switch node.storage {
        case let .leaf(kind):
            hasher.combine(kind)
        case let .container(owner):
            let children = owner.kind.hashChildless(into: &hasher)
            hasher.combine(children.count)
            pending.append(children)
        }
    }
}
