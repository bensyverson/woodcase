//
//  CRDTSnapshot.swift
//  Woodcase
//

import Foundation

/// A serializable snapshot of all ``CRDTDocument`` state.
///
/// `CRDTDocument` is neither `Sendable` nor `Codable` — it belongs to the isolation
/// domain of the ``EditableDocument`` it shadows — but its fields are individually
/// `Friendly`. `CRDTSnapshot` captures them as a `Sendable` value type that can cross
/// actor boundaries and serialize for network transfer — enabling the "Hot Swap"
/// scenario where a peer joins a live session from another peer's current state.
/// A snapshot and a ``CRDTOperation`` are the only two things that travel between
/// peers; the documents on either end never do.
///
/// ## Usage
///
/// ```swift
/// // Sender
/// let snapshot = crdtDocument.snapshot()
/// let data = try JSONEncoder().encode(snapshot)
/// // ... send data over network ...
///
/// // Receiver
/// let snapshot = try JSONDecoder().decode(CRDTSnapshot.self, from: data)
/// let doc = EditableDocument(from: penDocument, snapshot: snapshot, peerID: myPeerID)
/// ```
public struct CRDTSnapshot: Friendly {
    /// The peer that created this snapshot.
    public var peerID: PeerID

    /// The full operation log at snapshot time.
    public var operationLog: OperationLog

    /// Per-node LWW property timestamp maps.
    public var propertyMaps: [String: LWWPropertyMap]

    /// RGA-ordered children lists keyed by parent ID (or `"__root__"`).
    public var childrenLists: [String: RGAList<String>]

    /// The tree move CRDT state.
    public var treeMove: TreeMoveCRDT

    /// Node IDs that have been deleted (tombstoned).
    public var tombstones: Set<String>

    /// Timestamps for document-level variable writes.
    public var variableTimestamps: [String: Timestamp]

    /// Timestamps for document-level import writes.
    public var importTimestamps: [String: Timestamp]

    /// Timestamps for document-level theme axis writes.
    public var themeTimestamps: [String: Timestamp]

    /// Creates a snapshot with all CRDT state fields.
    public init(
        peerID: PeerID,
        operationLog: OperationLog,
        propertyMaps: [String: LWWPropertyMap],
        childrenLists: [String: RGAList<String>],
        treeMove: TreeMoveCRDT,
        tombstones: Set<String>,
        variableTimestamps: [String: Timestamp],
        importTimestamps: [String: Timestamp],
        themeTimestamps: [String: Timestamp]
    ) {
        self.peerID = peerID
        self.operationLog = operationLog
        self.propertyMaps = propertyMaps
        self.childrenLists = childrenLists
        self.treeMove = treeMove
        self.tombstones = tombstones
        self.variableTimestamps = variableTimestamps
        self.importTimestamps = importTimestamps
        self.themeTimestamps = themeTimestamps
    }
}
