//
//  CRDTDocument+DocumentProperties.swift
//  Woodcase
//

import Foundation

/// The document root's own properties as replica state.
///
/// Each key ``DocumentPropertyCodec`` names — `fonts`, `version`, `fileToken`, a table's
/// declaration (`variables`, `imports`, `themes`) and each root `extras.<key>` — is one
/// last-writer-wins register, carried as a ``CRDTOperation/SetDocumentProperty`` with the
/// key's value in .pen JSON shape; ``AnyCodable/null`` removes it. Keys are independent, so
/// two peers writing different root extras both keep theirs.
extension CRDTDocument {
    /// Records a local root patch and returns the operations to send: one per key whose
    /// value it changes, in key order.
    ///
    /// - Parameters:
    ///   - op: The patch, already validated.
    ///   - document: The document it is about to be applied to.
    /// - Returns: The operations to replicate; empty when the patch changes nothing or
    ///   will not resolve.
    func processLocalSetDocumentProperties(
        _ op: EditOperation.SetDocumentProperties,
        document: EditableDocument
    ) -> [CRDTOperation] {
        let before = DocumentPropertyCodec.root(of: document)
        guard let after = try? DocumentPropertyCodec.patched(op.properties, in: document) else { return [] }
        return op.properties.keys.sorted().compactMap { key in
            guard let value = try? DocumentPropertyCodec.value(at: key, of: after),
                  value != (try? DocumentPropertyCodec.value(at: key, of: before))
            else { return nil }
            let crdtOp = makeOp(.setDocumentProperty(CRDTOperation.SetDocumentProperty(key: key, value: value)))
            documentPropertyTimestamps[key] = crdtOp.id
            return crdtOp
        }
    }

    /// Applies a remote root-property write if it is newer than the key's last one.
    ///
    /// - Parameters:
    ///   - p: The write.
    ///   - timestamp: Its operation's id.
    /// - Returns: The mutation to apply, or `nil` when an equal or newer write won.
    func processRemoteSetDocumentProperty(_ p: CRDTOperation.SetDocumentProperty, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(
            key: p.key,
            timestamp: timestamp,
            timestamps: &documentPropertyTimestamps,
            mutation: .setDocumentProperty(key: p.key, value: p.value)
        )
    }
}
