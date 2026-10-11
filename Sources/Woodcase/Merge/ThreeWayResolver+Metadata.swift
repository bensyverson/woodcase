//
//  ThreeWayResolver+Metadata.swift
//  Woodcase
//

import Foundation

/// A node's metadata, merged per entry rather than as one value.
///
/// The change walk reports metadata as the one path `common.metadata`; merged whole,
/// one side's new tint on a note would collide with the other side's resolving it. So
/// it merges per entry (``NodePropertyCodec/metadataEntries(of:)``): each top-level key,
/// and each key under `metadata.woodcase`. A key both sides set differently keeps ours
/// and is reported at its entry path, such as `common.metadata.woodcase.state`. Metadata
/// the merge empties is removed, and metadata it leaves without a `type` takes
/// ``PenMetadata/woodcaseType``: a merge is a write, and Pen's schema requires one. Ours,
/// when the merge takes nothing of theirs, is left exactly as written.
extension ThreeWayResolver {
    /// Merges a node's metadata into `merged`.
    ///
    /// - Parameters:
    ///   - id: The node's id.
    ///   - base: The node in the base, or `nil` when both sides added it.
    ///   - ours: The local node.
    ///   - theirs: The external node.
    ///   - merged: The merged node, whose metadata is replaced.
    ///   - kind: The conflict kind for an entry both sides set differently.
    mutating func mergeMetadata(
        id: String, base: PenNode?, ours: PenNode, theirs: PenNode,
        into merged: inout PenNode, kind: MergeConflict.Kind
    ) {
        let entries = Self.mergeMap(
            NodePropertyCodec.metadataEntries(of: base?.common.metadata),
            NodePropertyCodec.metadataEntries(of: ours.common.metadata),
            NodePropertyCodec.metadataEntries(of: theirs.common.metadata)
        )
        for clash in entries.1 {
            report(.property(nodeID: id, path: clash.key), kind, base: clash.base, ours: clash.ours, theirs: clash.theirs)
        }
        // Nothing of theirs was taken: ours stands exactly as written, typed or not.
        guard entries.0 != NodePropertyCodec.metadataEntries(of: ours.common.metadata) else { return }
        var written = merged
        written.common.metadata = nil
        for (path, value) in entries.0.sorted(by: { $0.key < $1.key }) {
            written = NodePropertyCodec.settingMetadataEntry(value, at: path, on: written) ?? written
        }
        written.common.metadata = written.common.metadata?.typedForWriting()
        merged = written
    }
}
