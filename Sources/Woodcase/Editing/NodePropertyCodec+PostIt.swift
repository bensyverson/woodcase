//
//  NodePropertyCodec+PostIt.swift
//  Woodcase
//

import Foundation

/// The authoring check on a node's `metadata.woodcase`.
///
/// ``checkAuthored(_:on:)`` calls ``checkAuthoredPostIt(_:on:)`` for a `set`'s metadata,
/// after deep keys are folded, and the batch planner calls
/// ``checkAuthoredPostIts(in:current:)`` for every node of an `add` or `replace`
/// subtree. Both hold the write to ``PenPostIt``'s convention through
/// ``PenPostIt/violation(in:comparedTo:)``; a file is never checked on load.
public extension NodePropertyCodec {
    /// Refuses a whole `common.metadata` value that breaks the post-it convention.
    ///
    /// - Parameters:
    ///   - metadata: The metadata as it will be written; anything but an object passes.
    ///   - node: The node it will be written to; a key left at the value the node holds
    ///     is not checked.
    /// - Throws: ``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)``
    ///   for the first refused key.
    static func checkAuthoredPostIt(_ metadata: AnyCodable, on node: PenNode) throws {
        guard case let .dictionary(object) = metadata else { return }
        try check(object, comparedTo: node.common.metadata, nodeID: node.id)
    }

    /// Refuses a subtree, about to be inserted, holding a post-it that breaks the
    /// convention.
    ///
    /// - Parameters:
    ///   - subtree: The subtree, with its ids settled.
    ///   - current: The node each id names now, for a `replace`; a key left at the value
    ///     that node holds is not checked. An `add` passes a lookup that finds nothing.
    /// - Throws: ``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)``
    ///   for the first refused key, depth first.
    static func checkAuthoredPostIts(in subtree: PenNode, current: (String) -> PenNode?) throws {
        if let metadata = subtree.common.metadata {
            try check(metadata.object, comparedTo: current(subtree.id)?.common.metadata, nodeID: subtree.id)
        }
        for child in ComponentAnalyzer.childNodes(of: subtree) {
            try checkAuthoredPostIts(in: child, current: current)
        }
    }

    /// Throws the convention's first refusal of one metadata object.
    private static func check(
        _ object: [String: AnyCodable],
        comparedTo current: PenMetadata?,
        nodeID: String
    ) throws {
        guard let violation = PenPostIt.violation(in: object, comparedTo: current) else { return }
        throw EditingError.postItMetadataRejected(
            nodeID: nodeID,
            key: violation.key.path,
            value: PenPostIt.json(violation.value),
            accepted: violation.accepted,
            suggestion: violation.suggestion
        )
    }
}
