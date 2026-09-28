//
//  PenSubtreeDecoder.swift
//  Woodcase
//

import Foundation

/// Decodes an authored .pen subtree, marking the ids the author did not write.
///
/// ``PenNode`` requires an `id`, because every node in a real .pen file has one. A
/// subtree an agent writes for ``BatchOperation/add(_:)`` does not: an agent should
/// not have to invent ids to create nodes. So this fills any missing `id` with the
/// empty string, which ``SubtreeIDPlan`` reads as "none supplied" and draws one for.
///
/// ```swift
/// let raw: AnyCodable = ["type": "frame", "name": "Hero"]
/// let node = try PenSubtreeDecoder.node(from: raw)   // node.id is ""
/// ```
///
/// An id that *is* written survives both decoding and insertion: it is the id the
/// node ends up with, unless the document already holds it.
public enum PenSubtreeDecoder {
    /// The key a .pen node's inline children live under.
    private static let childrenKey = "children"

    /// The key a .pen node's id lives under.
    private static let idKey = "id"

    /// The `id` a node that wrote none carries out of decoding.
    ///
    /// Not a legal id — see ``PenID/isValid(_:)`` — which is the point: it cannot be
    /// mistaken for one the author meant.
    public static let unsuppliedID = ""

    /// Decodes a node from raw .pen JSON, marking any id the author omitted.
    ///
    /// The subtree is authored input, so it is decoded in ``PenDecodingMode/authoring``:
    /// a key its type does not claim — on a node, a fill, a stroke's paint or an effect —
    /// is refused rather than kept as a ``PenExtras``, and so is a fill or effect `type`
    /// this build does not model. A typo is caught instead of carried along.
    ///
    /// - Parameter value: The `node` field of a batch line, as raw JSON.
    /// - Returns: The decoded node, where an omitted id reads as ``unsuppliedID``.
    /// - Throws: Whatever ``PenNode`` throws for JSON that is not a node —
    ///   a missing `type`, a field of the wrong shape, or a key its type does not claim.
    public static func node(from value: AnyCodable) throws -> PenNode {
        let data = try JSONEncoder().encode(withPlaceholderIDs(value))
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        return try decoder.decode(PenNode.self, from: data)
    }

    /// Returns the same JSON with an `id` on every object that looks like a node
    /// and does not have one.
    ///
    /// - Parameter value: Raw .pen JSON for one node.
    /// - Returns: The value with placeholders filled in, recursively through `children`.
    static func withPlaceholderIDs(_ value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(fields) = value else { return value }

        if fields[idKey] == nil {
            fields[idKey] = .string(unsuppliedID)
        }
        if let existing = fields[childrenKey], case let .array(children) = existing {
            fields[childrenKey] = .array(children.map(withPlaceholderIDs))
        }
        return .dictionary(fields)
    }
}
