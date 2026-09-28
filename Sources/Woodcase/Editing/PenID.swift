//
//  PenID.swift
//  Woodcase
//

import Foundation

/// Utility for generating compact 5-character alphanumeric node IDs.
///
/// These IDs match the `.pen` format's own convention (e.g. `ALu8G`, `iYtnB`).
/// Uses `[a-zA-Z0-9]` charset with `SystemRandomNumberGenerator` for
/// collision resistance.
///
/// Generating is not the same as *accepting*: ``isValid(_:)`` is the wider rule an
/// id supplied by a caller has to satisfy.
public enum PenID {
    private static let charset: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Whether a string can be a node id.
    ///
    /// This is the .pen format's whole rule, and it is deliberately wide: an id is
    /// any non-empty string that contains no `/`. The format writes five alphanumerics and
    /// ``generate()`` draws from that space, but a supplied id is not held to that
    /// shape — `hero-card` is legal, and so is the `V:btnBase` an import prefix
    /// produces. The slash is the one character that cannot appear, because it
    /// separates the segments of a ``NodeAddress``: an id containing one could never
    /// be addressed afterwards.
    ///
    /// - Parameter id: The candidate id.
    /// - Returns: `true` when a node may carry it.
    public static func isValid(_ id: String) -> Bool {
        !id.isEmpty && !id.contains(NodeAddress.separator)
    }

    /// Generates a single compact 5-character alphanumeric ID.
    ///
    /// The ID space is 62^5 ≈ 916 million possible values,
    /// providing adequate collision resistance for typical document sizes.
    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0 ..< 5).map { _ in charset[Int(rng.next(upperBound: UInt64(charset.count)))] })
    }

    /// Generates a fresh ID that doesn't collide with any in the given set.
    ///
    /// - Parameter existing: Set of IDs to avoid.
    /// - Returns: A new unique ID.
    public static func generate(avoiding existing: Set<String>) -> String {
        var id = generate()
        while existing.contains(id) {
            id = generate()
        }
        return id
    }

    /// Remaps all IDs in a node tree to fresh compact IDs.
    ///
    /// A thin front door on ``SubtreeIDPlan/regenerating(_:avoiding:)`` for a caller
    /// that has no document to avoid — ref targets and `descendants` keys pointing
    /// *inside* the tree follow the nodes they name, exactly as they do for a `cp`.
    ///
    /// - Parameter node: The root of the node tree.
    /// - Returns: A tuple of the remapped node tree and the old→new ID mapping.
    public static func remapIDs(in node: PenNode) -> (PenNode, [String: String]) {
        let plan = SubtreeIDPlan.regenerating(node, avoiding: [])
        return (plan.applied(to: node), plan.replacements)
    }
}
