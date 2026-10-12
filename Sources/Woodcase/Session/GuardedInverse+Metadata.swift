//
//  GuardedInverse+Metadata.swift
//  Woodcase
//

import Foundation

/// Re-deriving a metadata entry's undo step against the node as it stands.
///
/// A step that restores one metadata entry carries the whole object as the write left
/// it, with the entry restored (``EditableDocument/metadataEntrySteps(writing:on:)``).
/// Applied as captured, it would also undo other authors' later writes to sibling
/// entries; resolved, it writes that one entry back onto the node's current metadata,
/// exactly, and keeps everything else.
extension GuardedInverse {
    /// The step as a write of the node's current metadata with this step's entry
    /// restored, or `nil` when the step does not restore one metadata entry.
    ///
    /// - Parameter document: The document the step is about to be applied to.
    /// - Returns: The operation to apply instead of ``operation``.
    func resolvedMetadataEntry(in document: EditableDocument) -> EditOperation? {
        let path = NodePropertyCodec.metadataPath
        guard case let .setProperties(op) = operation, op.properties.count == 1,
              let captured = op.properties[path],
              keys.count == 1, case let .property(nodeID, entryPath) = keys[0],
              nodeID == op.nodeID, entryPath.hasPrefix(path + "."),
              let current = document.nodes[nodeID],
              let restored = try? NodePropertyCodec.setting(captured, at: path, on: current),
              let written = NodePropertyCodec.settingMetadataEntry(
                  NodePropertyCodec.metadataEntries(of: restored.common.metadata)[entryPath] ?? .null,
                  at: entryPath,
                  on: current
              ),
              let value = try? NodePropertyCodec.value(at: path, of: written)
        else { return nil }
        return .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: [path: value]))
    }
}
