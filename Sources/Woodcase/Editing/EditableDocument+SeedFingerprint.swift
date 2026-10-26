//
//  EditableDocument+SeedFingerprint.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// The fingerprint of the document this replica's CRDT state was seeded from
    /// (``CRDTDocument/seedFingerprint``), or `nil` when the document is not collaborative.
    ///
    /// Equal on every replica made with ``init(from:peerID:)`` from an equal document,
    /// whatever its peer id; a replica made with ``init(joining:peerID:)`` reports its
    /// donor's. Edits never change it. See <doc:CRDTArchitecture#Seed-Fingerprint>.
    var seedFingerprint: SeedFingerprint? {
        crdtDocument?.seedFingerprint
    }
}
