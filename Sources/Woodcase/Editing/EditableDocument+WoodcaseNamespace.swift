//
//  EditableDocument+WoodcaseNamespace.swift
//  Woodcase
//

import Foundation

/// Moving a whole document's old-style Woodcase metadata under `metadata.woodcase`.
///
/// This is the rule `woodcase migrate` applies. Old spellings are still read, so the
/// migration changes no reading of the file; it is an ordinary edit — recorded in the
/// activity log and undoable — rather than part of the format migration, which never
/// changes a document. See <doc:PenMetadataNamespace>.
public extension EditableDocument {
    /// The edit that moves every old-style Woodcase metadata key in the document under
    /// `metadata.woodcase`.
    ///
    /// Each node's metadata becomes ``PenMetadata/migratingOldStyleWoodcaseKeys()`` of
    /// what it holds: the namespace keeps any key written in both spellings, and keys
    /// Woodcase no longer owns — a post-it's legacy `kind` — stay as written. Override
    /// patches inside a `ref`'s `descendants` are not rewritten; they are read through
    /// the same accessor, so their old spellings still work.
    ///
    /// ```swift
    /// for operation in document.oldStyleWoodcaseKeyMigration() {
    ///     try recorder.apply(operation)
    /// }
    /// ```
    ///
    /// - Returns: One `setProperties` of `common.metadata` per node that holds an old
    ///   spelling, in node-id order; empty when there is nothing to move.
    func oldStyleWoodcaseKeyMigration() -> [EditOperation] {
        nodes.keys.sorted().compactMap { id -> EditOperation? in
            guard let metadata = nodes[id]?.common.metadata, !metadata.oldStyleWoodcaseKeys.isEmpty else {
                return nil
            }
            let migrated = metadata.migratingOldStyleWoodcaseKeys()
            return .setProperties(EditOperation.SetProperties(
                nodeID: id,
                properties: [NodePropertyCodec.metadataPath: .dictionary(migrated.object)]
            ))
        }
    }
}
