//
//  PenNode+TreeDecoding.swift
//  Woodcase
//

import Foundation

/// Decoding a node's subtree from a work list.
///
/// Decoded the synthesized way, a frame decodes its children inside its own payload's
/// decoder, so every level of the tree holds a node's, a payload's and the JSON
/// decoder's frames on the stack at once — about 10 KB a level in a debug build, and a
/// Swift task's 512 KiB ran out on a frame tree some thirty-five deep. Here each node is
/// decoded **shallow** — its payload handed a ``ChildDeferringDecoder``, which sets the
/// `children` array aside — and the arrays set aside are walked from an explicit stack
/// on the heap. Only one node's decode is ever on the stack. See
/// `project/2026-09-26-debug-stack-depth.md`.
extension PenNode {
    /// Decodes a node and its whole subtree without recursion.
    ///
    /// - Parameter decoder: The node object's decoder.
    /// - Returns: The node, children decoded all the way down.
    /// - Throws: Whatever decoding any node in the subtree throws, with that node's
    ///   coding path.
    static func decodedTree(from decoder: Decoder) throws -> PenNode {
        let root = try shallow(from: decoder)
        guard let rootChildren = root.children else { return root.node }

        var stack = try [Level(node: root.node, children: rootChildren.unkeyedContainer())]
        while true {
            let last = stack.count - 1
            guard !stack[last].isAtEnd else {
                let finished = stack.removeLast()
                var node = finished.node
                node.kind = node.kind.replacingInlineChildren(with: finished.built)
                guard !stack.isEmpty else { return node }
                stack[stack.count - 1].built.append(node)
                continue
            }
            let child = try shallow(from: stack[last].nextDecoder())
            if let grandchildren = child.children {
                try stack.append(Level(node: child.node, children: grandchildren.unkeyedContainer()))
            } else {
                stack[last].built.append(child.node)
            }
        }
    }

    /// Decodes one node without its children.
    ///
    /// - Parameter decoder: The node object's decoder.
    /// - Returns: The node — a frame or group with its children still to come holding an
    ///   empty list — and the decoder positioned on those children, or `nil` when the
    ///   node has none to decode.
    /// - Throws: `DecodingError` as ``init(from:)`` describes.
    private static func shallow(from decoder: Decoder) throws -> (node: PenNode, children: Decoder?) {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let common = try PenNodeCommon(from: decoder)
        let typeString = try container.decode(String.self, forKey: .type)

        guard let nodeType = NodeType(rawValue: typeString) else {
            return try (unknown(typeString, id: id, common: common, from: decoder), nil)
        }
        let payloadDecoder = ChildDeferringDecoder(decoder)
        let kind = try Kind.decoding(nodeType, from: payloadDecoder)
        let extras = try Self.extras(of: nodeType, from: decoder)
        return (PenNode(id: id, common: common, kind: kind, extras: extras), payloadDecoder.children)
    }

    /// Decodes a node of a type this build does not model.
    ///
    /// A type this build does not model is kept from a file, and refused from an agent's
    /// input, where it is almost always a guess.
    private static func unknown(
        _ typeString: String,
        id: String,
        common: PenNodeCommon,
        from decoder: Decoder
    ) throws -> PenNode {
        guard PenDecodingMode.of(decoder) == .file else {
            throw unknownTypeRefusal(typeString, at: decoder.codingPath + [CodingKeys.type])
        }
        // Every non-reserved property is kept for round-tripping.
        let dynContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var props: [String: AnyCodable] = [:]
        for key in dynContainer.allKeys where !Self.sharedKeys.contains(key.stringValue) {
            props[key.stringValue] = try dynContainer.decode(AnyCodable.self, forKey: key)
        }
        return PenNode(id: id, common: common, kind: .unknown(typeName: typeString, properties: props), extras: PenExtras())
    }

    /// One node whose children are being decoded.
    private struct Level {
        /// The node, its children not yet attached.
        let node: PenNode

        /// Its `children` array, read one element at a time.
        var children: UnkeyedDecodingContainer

        /// The children decoded so far, in order.
        var built: [PenNode] = []

        /// Whether every child has been read.
        var isAtEnd: Bool {
            children.isAtEnd
        }

        /// The decoder for the next child.
        mutating func nextDecoder() throws -> Decoder {
            try children.superDecoder()
        }
    }
}
