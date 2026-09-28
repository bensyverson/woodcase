//
//  PenNode+ClaimedKeys.swift
//  Woodcase
//

import Foundation

/// Which keys of a node object the model claims, and so which ones are ``PenNode/extras``.
extension PenNode {
    /// The keys every node claims whatever its type: `id`, `type` and the shared
    /// properties ``PenNodeCommon`` decodes.
    static let sharedKeys: Set<String> = Set(["id", "type"])
        .union(NodePropertyCodec.commonPaths.map(NodePropertyCodec.rawKey(for:)))

    /// Every key a node of each modelled type claims.
    ///
    /// Read off the property vocabulary ``PropertyDiff/allKindKeys(_:)-(PenNode.NodeType)``
    /// already keeps — the one `set` and `woodcase schema` answer from — in the file's own
    /// spelling (`fills` is `fill`), plus `children` for the two containers, which the
    /// vocabulary leaves to the tree. A key a `*Data` decoder reads must be in that
    /// vocabulary, or it would be decoded *and* kept as an extra; `set` already needs it
    /// there to write the key at all.
    static let claimedKeys: [NodeType: Set<String>] = Dictionary(uniqueKeysWithValues: NodeType.allCases.map { type in
        let kindKeys = PropertyDiff.allKindKeys(type).map(NodePropertyCodec.rawKey(for:))
        let containerKeys: Set<String> = type == .frame || type == .group ? ["children"] : []
        return (type, sharedKeys.union(kindKeys).union(containerKeys))
    })

    /// Reads the keys of the node object at `decoder` that a node of `type` does not claim.
    ///
    /// A `ref` has none by construction — every key it does not claim is a root
    /// override (``RefData/rootOverrides``) — and neither does a node of an unknown type,
    /// whose keys are all ``Kind/unknown(typeName:properties:)`` properties.
    ///
    /// - Parameters:
    ///   - type: The node's modelled type.
    ///   - decoder: The decoder positioned at the node object.
    /// - Returns: The node's extras.
    /// - Throws: `DecodingError` for an unclaimed key in ``PenDecodingMode/authoring``.
    static func extras(of type: NodeType, from decoder: Decoder) throws -> PenExtras {
        guard type != .ref, let claimed = claimedKeys[type] else { return PenExtras() }
        return try PenExtras.capture(from: decoder, claiming: claimed, describing: "a \(type.rawValue) node")
    }
}
