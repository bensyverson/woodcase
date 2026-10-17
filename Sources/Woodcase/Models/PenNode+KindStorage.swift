//
//  PenNode+KindStorage.swift
//  Woodcase
//

import Foundation

/// Where a node keeps its ``PenNode/Kind``, and how a deep tree is freed without
/// recursing.
///
/// Swift frees a value by freeing everything it holds, so dropping the last reference to
/// a tree used to free it one call per level — about 770 bytes a level in a debug build —
/// and a tree deep enough overflowed a Swift task's 512 KiB stack in the free alone. A
/// struct or enum has no `deinit` to stop that; a class does. So a node whose kind holds
/// children keeps it in a ``SubtreeOwner``, and the owner's `deinit` takes the tree apart
/// from a work list: before a child is released, its own children are moved onto the
/// list, so no release ever has a subtree beneath it. A node without children keeps its
/// kind inline and costs nothing extra. See `project/2026-09-26-debug-stack-depth.md`.
extension PenNode {
    /// A node's kind: inline when it holds no children, in a ``SubtreeOwner`` when it does.
    ///
    /// Which one is a function of the kind alone — whether
    /// ``Kind/inlineChildrenIfPresent`` is non-empty — so two equal nodes always store
    /// their kinds the same way.
    enum KindStorage {
        /// A kind with no children to free.
        case leaf(Kind)

        /// A kind with children, held by an owner that frees them iteratively.
        case container(SubtreeOwner)

        /// Stores a kind the way its children call for.
        ///
        /// - Parameter kind: The kind.
        init(_ kind: Kind) {
            if let children = kind.inlineChildrenIfPresent, !children.isEmpty {
                self = .container(SubtreeOwner(kind))
            } else {
                self = .leaf(kind)
            }
        }

        /// The kind stored.
        var kind: Kind {
            switch self {
            case let .leaf(kind): kind
            case let .container(owner): owner.kind
            }
        }
    }

    /// The box a container's kind lives in, whose `deinit` frees the subtree beneath it
    /// from a work list.
    ///
    /// `@unchecked Sendable`: ``kind`` is only ever written by ``surrender()``, which runs
    /// either in `deinit` or on an owner the caller has just proved it holds the only
    /// reference to (`isKnownUniquelyReferenced`). No other thread can see the write.
    final class SubtreeOwner: @unchecked Sendable {
        /// The kind, until the owner surrenders its children.
        private(set) var kind: Kind

        /// Holds a kind.
        ///
        /// - Parameter kind: A kind with inline children.
        init(_ kind: Kind) {
            self.kind = kind
        }

        deinit {
            var pending = surrender()
            while var node = pending.popLast() {
                node.surrenderChildren(into: &pending)
            }
        }

        /// Takes the kind's children out and leaves ``PenNode/vacatedKind`` in its place,
        /// so releasing the kind frees no subtree.
        ///
        /// - Returns: The children, whose last reference is now the caller's whenever the
        ///   kind's was the owner's.
        fileprivate func surrender() -> [PenNode] {
            let children = kind.inlineChildren
            kind = PenNode.vacatedKind
            return children
        }
    }

    /// What a surrendered owner, or a node whose owner was taken, holds instead: a kind
    /// with no children, shared, so taking a tree apart allocates nothing.
    static let vacatedKind = Kind.unknown(typeName: "", properties: [:])

    /// Moves this node's children onto `pending` if nothing else holds its kind, so that
    /// releasing the node frees no subtree.
    ///
    /// Only for a node about to be released: it leaves the node holding
    /// ``vacatedKind``. A kind something else still holds is left whole — its children
    /// are not this release's to free.
    ///
    /// - Parameter pending: The work list of nodes still to release.
    private mutating func surrenderChildren(into pending: inout [PenNode]) {
        guard case var .container(owner) = storage else { return }
        storage = .leaf(Self.vacatedKind)
        guard isKnownUniquelyReferenced(&owner) else { return }
        pending.append(contentsOf: owner.surrender())
    }
}
