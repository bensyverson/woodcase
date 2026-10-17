//
//  PenNode+TreeEncoding.swift
//  Woodcase
//

import Foundation

/// Encoding a node's subtree from a work list.
///
/// Encoded the synthesized way, a frame encodes its children inside its own payload's
/// `encode(to:)`, so every level of the tree held a node's, a payload's, an array's and
/// the encoder's frames on the stack at once — about 11 KB a level in a debug build.
/// Here each node is encoded **shallow** — its payload with `children` set to `nil` — and
/// its `children` array is opened as a nested container the walk fills later, each child
/// through a `superEncoder()` of that container. Only one node's encode is ever on the
/// stack. The mirror of ``PenNode/decodedTree(from:)``; see
/// `project/2026-09-26-debug-stack-depth.md`.
///
/// A super-encoder writes what it was given into its container when it is released, at
/// the place it was created for, so each level keeps its node's encoder until the
/// node's last child is done, and a sibling's encoder is made only after the one before
/// it is released.
extension PenNode {
    /// The key a container's children are written under, in a frame and a group alike.
    private enum ChildrenKey: String, CodingKey {
        case children
    }

    /// One container whose children are being encoded.
    private struct Level {
        /// The container's encoder, kept until its children are written.
        let encoder: Encoder

        /// Its `children` array, written one element at a time.
        var container: UnkeyedEncodingContainer

        /// The children.
        let nodes: [PenNode]

        /// The index of the next child to write.
        var next = 0
    }

    /// Encodes a node and its whole subtree without recursion.
    ///
    /// - Parameter encoder: The node object's encoder.
    /// - Throws: Whatever encoding any node in the subtree throws.
    func encodeTree(to encoder: Encoder) throws {
        guard let children = try encodeShallow(to: encoder) else { return }
        var stack = [Self.level(for: children, in: encoder)]
        while let last = stack.indices.last {
            let index = stack[last].next
            guard index < stack[last].nodes.count else {
                stack.removeLast()
                continue
            }
            stack[last].next = index + 1
            let child = stack[last].nodes[index]
            let childEncoder = stack[last].container.superEncoder()
            if let grandchildren = try child.encodeShallow(to: childEncoder) {
                stack.append(Self.level(for: grandchildren, in: childEncoder))
            }
        }
    }

    /// Opens a container's `children` array.
    private static func level(for children: [PenNode], in encoder: Encoder) -> Level {
        var keyed = encoder.container(keyedBy: ChildrenKey.self)
        return Level(encoder: encoder, container: keyed.nestedUnkeyedContainer(forKey: .children), nodes: children)
    }

    /// Encodes one node without its children.
    ///
    /// - Parameter encoder: The node object's encoder.
    /// - Returns: The children still to write under `children` — empty for a container
    ///   that declares an empty list — or `nil` when the node writes no `children` key.
    /// - Throws: Whatever the encoder throws.
    private func encodeShallow(to encoder: Encoder) throws -> [PenNode]? {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)

        let kind = kind
        guard let payload = kind.childlessEncodablePayload else {
            try encodeUnknown(into: encoder, container: &container)
            return nil
        }
        try container.encode(kind.typeName, forKey: .type)
        try common.encode(to: encoder)
        try payload.encode(to: encoder)
        return kind.inlineChildrenIfPresent
    }
}
