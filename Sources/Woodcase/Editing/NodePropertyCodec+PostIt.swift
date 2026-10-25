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
/// ``PenPostIt/violation(in:comparedTo:on:)``; a file is never checked on load.
public extension NodePropertyCodec {
    /// Refuses a whole `common.metadata` value that breaks the post-it convention.
    ///
    /// - Parameters:
    ///   - metadata: The metadata as it will be written; anything but an object passes.
    ///   - node: The node it will be written to; a key left at the value the node holds
    ///     is not checked.
    /// - Throws: ``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)``
    ///   for the first refused key, or ``EditingError/textSpansRejected(nodeID:reason:)``
    ///   when that key is malformed spans.
    static func checkAuthoredPostIt(_ metadata: AnyCodable, on node: PenNode) throws {
        guard case let .dictionary(object) = metadata else { return }
        try check(object, comparedTo: node.common.metadata, kind: node.kind, nodeID: node.id)
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
            try check(
                metadata.object, comparedTo: current(subtree.id)?.common.metadata, kind: subtree.kind, nodeID: subtree.id
            )
        }
        for child in ComponentAnalyzer.childNodes(of: subtree) {
            try checkAuthoredPostIts(in: child, current: current)
        }
    }

    /// Refuses the metadata of an instance override that breaks the convention: what a
    /// descendant's `descendants` entry, or a `ref` node for its root, will lay over the
    /// component node's metadata key by key (rule 6). Held to the same shapes a `set` is,
    /// so malformed spans inside an instance are refused as they are on a plain text.
    ///
    /// - Parameters:
    ///   - metadata: The override's metadata as it will be written; anything but an object
    ///     passes.
    ///   - definition: The node the override patches, as this instance already shows it; a
    ///     key left at the value it shows is not checked. `nil` checks every key.
    ///   - nodeID: The node the refusal names: the instance's expanded id for a descendant.
    /// - Throws: ``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)``
    ///   or ``EditingError/textSpansRejected(nodeID:reason:)``, as ``checkAuthoredPostIt(_:on:)``.
    static func checkAuthoredOverrideMetadata(_ metadata: AnyCodable, on definition: PenNode?, nodeID: String) throws {
        guard case let .dictionary(object) = metadata else { return }
        try check(object, comparedTo: definition?.common.metadata, kind: definition?.kind, nodeID: nodeID)
    }

    /// Throws the convention's first refusal of one metadata object.
    private static func check(
        _ object: [String: AnyCodable],
        comparedTo current: PenMetadata?,
        kind: PenNode.Kind?,
        nodeID: String
    ) throws {
        guard let violation = PenPostIt.violation(in: object, comparedTo: current, on: kind) else { return }
        if let reason = violation.reason {
            throw EditingError.textSpansRejected(nodeID: nodeID, reason: reason)
        }
        throw EditingError.postItMetadataRejected(
            nodeID: nodeID,
            // The key as the metadata object spells it; the planner names it as the caller
            // wrote it (`EditPlanner.spelling(of:asWritten:)`).
            key: violation.key.path,
            value: PenPostIt.json(violation.value),
            accepted: violation.accepted,
            suggestion: violation.suggestion
        )
    }
}
