//
//  CRDTDocument+Metadata.swift
//  Woodcase
//

import Foundation

/// A node's metadata replicates one entry at a time.
///
/// A local change to `common.metadata` — a whole-object write is what a `set` folds to —
/// is sent as one LWW write per entry that changed
/// (``NodePropertyCodec/metadataEntryWrites(from:to:)``), never as the whole object, so
/// two peers editing different keys of one note's metadata both keep their edit, and a
/// whole-object write never races an entry write. See <doc:PenMetadataNamespace>.
extension CRDTDocument {
    /// Records a local change of a node's metadata and returns the ops to send.
    ///
    /// - Parameters:
    ///   - nodeID: The node whose metadata changed.
    ///   - old: Its metadata before the change.
    ///   - new: Its metadata after.
    /// - Returns: One ``CRDTOperation/SetProperty`` per entry that changed.
    func processLocalMetadata(nodeID: String, from old: PenMetadata?, to new: PenMetadata?) -> [CRDTOperation] {
        NodePropertyCodec.metadataEntryWrites(from: old, to: new).map { entry in
            let op = makeOp(.setProperty(CRDTOperation.SetProperty(
                nodeID: nodeID,
                property: entry.path,
                value: entry.value
            )))
            propertyMaps[nodeID, default: LWWPropertyMap()].record(property: entry.path, at: op.id)
            return op
        }
    }
}
