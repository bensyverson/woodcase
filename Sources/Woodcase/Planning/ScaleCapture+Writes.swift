//
//  ScaleCapture+Writes.swift
//  Woodcase
//

import Foundation

/// Routing a node's scaled properties to where they are stored.
extension ScaleCapture {
    /// The edits that write `properties` on what is drawn at `entry`, wherever it is stored.
    ///
    /// A node with storage of its own takes them as one `setProperties`, unplanned: every
    /// value is one the node already held, multiplied by a positive factor, so the
    /// planner's checks have nothing to refuse, and skipping them keeps a step cheap enough
    /// for every display refresh. An instance root splits them:
    /// its `common` properties — `x`, `y` — are the `ref` node's own, and the component
    /// root's properties as the instance shows them are root overrides. A node inside an
    /// instance stores nothing of its own, so everything is an override on the instance.
    /// ``EditPlanner`` plans each override, translating paths to the raw keys the instance
    /// stores, so a scale and an inspector write an override the same way.
    ///
    /// - Throws: The ``EditRefusal`` the planner raises.
    static func writes(
        _ properties: [String: AnyCodable], for entry: Entry, in document: EditableDocument
    ) throws(EditRefusal) -> [EditOperation] {
        guard !properties.isEmpty else { return [] }
        switch entry.address {
        case let .node(id):
            guard case .ref? = document.node(id: id)?.kind else {
                return [ownWrite(properties, on: id, in: document)]
            }
            let own = properties.filter { $0.key.hasPrefix(NodePropertyCodec.commonPrefix) }
            let overridden = properties.filter { !$0.key.hasPrefix(NodePropertyCodec.commonPrefix) }
            var operations: [EditOperation] = []
            if !own.isEmpty {
                operations.append(ownWrite(own, on: id, in: document))
            }
            if !overridden.isEmpty {
                operations += try EditPlanner.plan(.override(overridden), at: entry.address, in: document).operations
            }
            return operations
        case .instanceDescendant:
            return try EditPlanner.plan(.override(properties), at: entry.address, in: document).operations
        }
    }

    /// A `setProperties` on a node's own storage, its deep metadata keys folded onto the
    /// metadata the node carries (``EditOperation/normalized(in:)``), as the planner folds
    /// them, so the edit applies as it stands.
    private static func ownWrite(
        _ properties: [String: AnyCodable], on id: String, in document: EditableDocument
    ) -> EditOperation {
        let write = EditOperation.setProperties(EditOperation.SetProperties(nodeID: id, properties: properties))
        return properties.keys.contains { $0.hasPrefix(metadataPrefix) } ? write.normalized(in: document) : write
    }

    /// The prefix of a deep metadata key.
    private static let metadataPrefix = "common.metadata."
}
