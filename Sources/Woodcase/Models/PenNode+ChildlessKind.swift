//
//  PenNode+ChildlessKind.swift
//  Woodcase
//

import Foundation

/// A container's kind compared, hashed and encoded without its children, for the walks
/// that take the children from a work list instead.
///
/// Each takes `children` out of a copy of the payload and hands the copy to the payload's
/// own synthesized conformance, so every other field is covered without being named — a
/// field added to a payload is compared, hashed and encoded with no change here. (Naming
/// the fields instead saved nothing in release and made a debug `==` 70% slower:
/// `PenNodeTreeCostProbe`, 2026-10-17, now `WoodcaseBench node-tree-cost`.)
///
/// The containers are the kinds ``Kind/inlineChildrenIfPresent`` lists; a new kind with
/// children must join it, ``Kind/replacingInlineChildren(with:)`` and the switches here.
/// Every other kind is compared and hashed whole, by its synthesized conformance.
extension PenNode.Kind {
    /// Compares two kinds on everything but their children, and returns the children.
    ///
    /// - Parameters:
    ///   - lhs: A kind.
    ///   - rhs: Another kind.
    /// - Returns: Both kinds' children — empty for a kind without any — when the kinds
    ///   are the same case and match on everything else, or `nil`.
    static func childlessMatch(_ lhs: Self, _ rhs: Self) -> PenNode.SiblingPair? {
        switch lhs {
        case var .frame(lhsShell):
            guard case var .frame(rhsShell) = rhs else { return nil }
            let lhsChildren = lhsShell.children.take()
            let rhsChildren = rhsShell.children.take()
            guard (lhsChildren == nil) == (rhsChildren == nil), lhsShell == rhsShell else { return nil }
            return PenNode.SiblingPair(lhs: lhsChildren ?? [], rhs: rhsChildren ?? [])
        case var .group(lhsShell):
            guard case var .group(rhsShell) = rhs else { return nil }
            let lhsChildren = lhsShell.children.take()
            let rhsChildren = rhsShell.children.take()
            guard (lhsChildren == nil) == (rhsChildren == nil), lhsShell == rhsShell else { return nil }
            return PenNode.SiblingPair(lhs: lhsChildren ?? [], rhs: rhsChildren ?? [])
        default:
            return lhs == rhs ? PenNode.SiblingPair(lhs: [], rhs: []) : nil
        }
    }

    /// Hashes the kind on everything but its children, and returns the children.
    ///
    /// - Parameter hasher: The hasher to feed.
    /// - Returns: The kind's children, empty for a kind without any.
    func hashChildless(into hasher: inout Hasher) -> [PenNode] {
        switch self {
        case var .frame(shell):
            let children = shell.children.take()
            hasher.combine(PenNode.NodeType.frame)
            hasher.combine(shell)
            hasher.combine(children == nil)
            return children ?? []
        case var .group(shell):
            let children = shell.children.take()
            hasher.combine(PenNode.NodeType.group)
            hasher.combine(shell)
            hasher.combine(children == nil)
            return children ?? []
        default:
            hasher.combine(self)
            return []
        }
    }

    /// The payload of a modeled kind without its children, ready to encode, or `nil`
    /// for an unknown one.
    var childlessEncodablePayload: (any Encodable)? {
        switch self {
        case var .frame(data):
            data.children = nil
            return data
        case var .group(data):
            data.children = nil
            return data
        default:
            return encodablePayload
        }
    }

    /// Whether two kinds are one value: the same case in the same `indirect` box.
    ///
    /// A kind is one reference to an immutable box, so two whose bits match hold the
    /// same payload and are equal without reading it — the shortcut `Array`'s `==` takes
    /// for a shared buffer. Trees materialized from the same flat store share every
    /// childless node's box, which is what Penumbra compares on every edit. A `false`
    /// says nothing; the caller compares the payloads.
    ///
    /// - Parameters:
    ///   - lhs: A kind.
    ///   - rhs: Another kind.
    /// - Returns: `true` when both are the same box.
    static func sameBox(_ lhs: Self, _ rhs: Self) -> Bool {
        guard MemoryLayout<Self>.size == MemoryLayout<UInt>.size else { return false }
        return withUnsafeBytes(of: lhs) { $0.load(as: UInt.self) } == withUnsafeBytes(of: rhs) { $0.load(as: UInt.self) }
    }
}
