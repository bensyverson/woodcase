//
//  EditableDocument+MetadataInverse.swift
//  Woodcase
//

import Foundation

/// A `common.metadata` write undoes one entry at a time.
///
/// The write is keyed per entry it changes (``ChangeKey/propertyKeys(_:in:)``), so its
/// undo is one step per entry, each guarded by that entry's key: an entry another
/// author has since written is kept, and the others are restored around it.
///
/// Each step's operation writes the whole object — the metadata the write leaves, with
/// this entry and every step before it restored — so the steps, replayed in order on
/// the document the write left (an activity row's inverse, a batch's undo), restore it
/// exactly, and the last step alone does too. A session's undo re-derives the step
/// against the node as it stands (``GuardedInverse/resolved(in:)``), restoring that one
/// entry exactly. Neither goes through the deep-key fold, whose namespace rules would
/// move an old spelling back into the namespace rather than restore it.
extension EditableDocument {
    /// The steps that undo a write of `common.metadata`: one per entry it changes.
    ///
    /// - Parameters:
    ///   - value: The whole metadata object the write stores.
    ///   - node: The node, before the write.
    /// - Returns: The steps, sorted by entry path.
    /// - Throws: ``EditingError`` if `value` is not metadata.
    func metadataEntrySteps(writing value: AnyCodable, on node: PenNode) throws -> [GuardedInverse] {
        let path = NodePropertyCodec.metadataPath
        let after = try NodePropertyCodec.setting(value, at: path, on: node)
        let before = NodePropertyCodec.metadataEntries(of: node.common.metadata)
        var restoring = after
        return try NodePropertyCodec.metadataEntryWrites(from: node.common.metadata, to: after.common.metadata).map { entry in
            let old = before[entry.path] ?? .null
            restoring = NodePropertyCodec.settingMetadataEntry(old, at: entry.path, on: restoring) ?? restoring
            return try GuardedInverse(
                operation: .setProperties(EditOperation.SetProperties(
                    nodeID: node.id,
                    properties: [path: NodePropertyCodec.value(at: path, of: restoring)]
                )),
                keys: [.property(node: node.id, path: entry.path)]
            )
        }
    }
}
