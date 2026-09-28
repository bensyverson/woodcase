//
//  NodePropertyCodec+OverrideKeys.swift
//  Woodcase
//

import Foundation

/// What a node's own JSON object holds, and what it would accept — the two sets an
/// override has to be judged against.
///
/// An override is merged onto a node's raw JSON at expansion time
/// (``PenNodePatcher/patchNode(_:with:)``), so "does this override replace a value or
/// add one?" is a question about the node's stored keys, and "will anything ever read
/// it?" is a question about the keys its type accepts. Neither is answerable from a
/// property path alone, which is why both live here rather than in a caller.
extension NodePropertyCodec {
    /// The raw .pen keys a node's own JSON object carries.
    ///
    /// - Parameter node: The node to read.
    /// - Returns: Its top-level keys, or `nil` if the node will not encode.
    static func storedKeys(of node: PenNode) -> Set<String>? {
        guard let data = try? JSONEncoder().encode(node),
              let object = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
        else { return nil }
        return Set(object.keys)
    }

    /// The raw .pen keys a node of this kind accepts, shared properties included.
    ///
    /// The property vocabulary is only half the answer. A node's JSON object also holds
    /// keys that are *structure* rather than properties — `children` on a container —
    /// and the merge decodes those as readily as the rest, which is how an instance
    /// fills a slot. Those come from ``PenNodePatcher/structuralKeys(of:)``, so this
    /// set is the patcher's contract rather than a second reading of it.
    ///
    /// - Parameter node: The node whose type sets the vocabulary.
    /// - Returns: Every key ``PenNodePatcher`` could merge onto it and have survive the
    ///   round trip back into a ``PenNode``.
    static func rawKeys(acceptedBy node: PenNode) -> Set<String> {
        let paths = PropertyDiff.allKindKeys(node.kind).union(commonPaths)
        return Set(paths.map { rawKey(for: $0) })
            .union(PenNodePatcher.structuralKeys(of: node))
    }
}
