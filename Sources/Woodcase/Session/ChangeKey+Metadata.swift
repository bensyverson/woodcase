//
//  ChangeKey+Metadata.swift
//  Woodcase
//

import Foundation

/// A metadata write is keyed per entry it changes.
///
/// The CRDT replicates `common.metadata` one entry at a time
/// (``NodePropertyCodec/metadataEntryWrites(from:to:)``), so a collaborator's write
/// arrives keyed by its entry path — `common.metadata.woodcase.tint` — through
/// ``keys(ofRemote:in:)``. A local write must stamp the same keys, or an undo of it would
/// neither see that collaborator's later write to the entry nor leave their sibling
/// entries alone.
extension ChangeKey {
    /// The keys a property write changes: one per path, except `common.metadata`, which
    /// is one per entry the write changes.
    ///
    /// - Parameters:
    ///   - op: The write, deep keys already folded (``EditOperation/normalized(in:)``).
    ///   - document: The document it will be applied to, as it stands.
    /// - Returns: The keys, sorted by path.
    static func propertyKeys(_ op: EditOperation.SetProperties, in document: EditableDocument) -> [ChangeKey] {
        op.properties.keys.sorted().flatMap { path -> [ChangeKey] in
            guard path == NodePropertyCodec.metadataPath,
                  let node = document.nodes[op.nodeID],
                  let value = op.properties[path],
                  let written = try? NodePropertyCodec.setting(value, at: path, on: node)
            else { return [.property(node: op.nodeID, path: path)] }
            return metadataKeys(nodeID: op.nodeID, from: node.common.metadata, to: written.common.metadata)
        }
    }

    /// The keys of the `common.*` paths that differ between two versions of a node's
    /// shared properties, `common.metadata` per entry.
    ///
    /// - Parameters:
    ///   - nodeID: The node.
    ///   - old: Its shared properties before.
    ///   - new: Its shared properties after.
    /// - Returns: The keys, sorted by path.
    static func commonKeys(nodeID: String, old: PenNodeCommon, new: PenNodeCommon) -> [ChangeKey] {
        PropertyDiff.diffCommon(old: old, new: new).sorted().flatMap { path -> [ChangeKey] in
            guard path == NodePropertyCodec.metadataPath else { return [.property(node: nodeID, path: path)] }
            return metadataKeys(nodeID: nodeID, from: old.metadata, to: new.metadata)
        }
    }

    /// The keys of the metadata entries that differ between two metadata objects.
    ///
    /// - Parameters:
    ///   - nodeID: The node whose metadata changes.
    ///   - old: Its metadata before.
    ///   - new: Its metadata after.
    /// - Returns: One key per entry that differs, sorted by path.
    static func metadataKeys(nodeID: String, from old: PenMetadata?, to new: PenMetadata?) -> [ChangeKey] {
        NodePropertyCodec.metadataEntryWrites(from: old, to: new).map { .property(node: nodeID, path: $0.path) }
    }
}
