//
//  CRDTDocument.swift
//  Woodcase
//

import Foundation

/// The CRDT state machine for collaborative editing.
///
/// `CRDTDocument` owns all CRDT metadata — timestamps, LWW property maps,
/// RGA child-ordering lists, and the Kleppmann tree move log. It sits alongside
/// ``EditableDocument`` as a shadow structure: the flat store remains the
/// `@Observable` materialized view that SwiftUI observes, while `CRDTDocument`
/// provides the convergence guarantees.
///
/// ## Two Processing Paths
///
/// - ``processLocal(operation:document:)`` — translates an ``EditOperation``
///   into ``CRDTOperation``s for replication. The app sends these to other peers.
/// - ``processRemote(operation:document:)`` — applies a ``CRDTOperation`` from
///   another peer, resolves conflicts, and returns ``DocumentMutation``s for
///   the flat store.
///
/// ## Ownership Boundary
///
/// Woodcase owns convergence. The consuming app owns persistence and transport:
/// it calls ``pendingOperations(since:)`` to get ops to store/send, and
/// ``processRemote(operation:document:)`` to replay ops from storage or network.
public final class CRDTDocument {
    /// This peer's identifier.
    public let peerID: PeerID

    /// The operation log (also owns the Lamport clock and vector clock).
    public internal(set) var operationLog: OperationLog

    /// Per-node property timestamp maps for LWW resolution.
    public internal(set) var propertyMaps: [String: LWWPropertyMap]

    /// RGA lists for ordered children. Key is parent ID or `"__root__"` for root order.
    public internal(set) var childrenLists: [String: RGAList<String>]

    /// The tree move CRDT for structural convergence.
    public internal(set) var treeMove: TreeMoveCRDT

    /// Node IDs that have been deleted (tombstoned).
    public internal(set) var tombstones: Set<String>

    /// Timestamps for document-level variable writes.
    public internal(set) var variableTimestamps: [String: Timestamp]

    /// Timestamps for document-level import writes.
    public internal(set) var importTimestamps: [String: Timestamp]

    /// Timestamps for document-level theme axis writes.
    public internal(set) var themeTimestamps: [String: Timestamp]

    /// The sentinel key used for root-level children lists.
    public static let rootListID = "__root__"

    /// Creates a CRDT document from the current state of an ``EditableDocument``.
    ///
    /// Initializes all CRDT metadata (RGA lists, tree move state, property maps)
    /// from the existing flat store. All initial entries use a zero timestamp.
    ///
    /// - Parameters:
    ///   - peerID: This peer's unique identifier.
    ///   - document: The editable document to shadow.
    public init(peerID: PeerID, document: EditableDocument) {
        self.peerID = peerID
        operationLog = OperationLog(peerID: peerID)
        propertyMaps = [:]
        childrenLists = [:]
        tombstones = []
        variableTimestamps = [:]
        importTimestamps = [:]
        themeTimestamps = [:]

        // Build initial parent map for tree move CRDT
        var initialParentMap: [String: String?] = [:]
        for nodeID in document.nodes.keys {
            initialParentMap[nodeID] = document.parents[nodeID]
        }
        treeMove = TreeMoveCRDT(initialParentMap: initialParentMap)

        // Build RGA lists from existing child ordering.
        // Use the genesis peer ID so all replicas share the same position IDs
        // for the initial document state.
        let genesisPeer = PeerID.genesis

        // Root order
        var rootList = RGAList<String>()
        var lastPos: PositionID?
        for (i, childID) in document.rootOrder.enumerated() {
            let ts = Timestamp(time: UInt64(i), peerID: genesisPeer)
            lastPos = rootList.insert(childID, after: lastPos, timestamp: ts)
        }
        childrenLists[Self.rootListID] = rootList

        // Children lists for each parent
        for (parentID, childIDs) in document.children {
            var list = RGAList<String>()
            var prevPos: PositionID?
            for (i, childID) in childIDs.enumerated() {
                let ts = Timestamp(time: UInt64(i), peerID: genesisPeer)
                prevPos = list.insert(childID, after: prevPos, timestamp: ts)
            }
            childrenLists[parentID] = list
        }

        // Ensure the clock starts past any initial timestamps
        // Initialize property maps (empty — first edit will record timestamps)
        for nodeID in document.nodes.keys {
            propertyMaps[nodeID] = LWWPropertyMap()
        }
    }

    /// Creates a CRDT document with a pre-built operation log and empty state.
    ///
    /// Used by ``init(from:peerID:)`` to bootstrap from a ``CRDTSnapshot``
    /// without requiring an ``EditableDocument``. The caller is responsible
    /// for populating the remaining state fields after initialization.
    ///
    /// - Parameters:
    ///   - peerID: This peer's unique identifier.
    ///   - bootstrapOperationLog: An existing operation log to adopt.
    init(peerID: PeerID, bootstrapOperationLog: OperationLog) {
        self.peerID = peerID
        operationLog = bootstrapOperationLog
        propertyMaps = [:]
        childrenLists = [:]
        treeMove = TreeMoveCRDT(initialParentMap: [:])
        tombstones = []
        variableTimestamps = [:]
        importTimestamps = [:]
        themeTimestamps = [:]
    }

    // MARK: - Local operation processing

    /// Translates an ``EditOperation`` into ``CRDTOperation``s for replication.
    ///
    /// Call this when the local user performs an edit. The returned operations
    /// should be sent to other peers for convergence.
    ///
    /// - Parameters:
    ///   - operation: The local edit operation.
    ///   - document: The current flat store (read for diffing).
    /// - Returns: An array of CRDT operations to replicate.
    public func processLocal(operation: EditOperation, document: EditableDocument) -> [CRDTOperation] {
        switch operation {
        case let .insertNode(op):
            processLocalInsert(op, document: document)
        case let .deleteNode(op):
            processLocalDelete(op, document: document)
        case let .moveNode(op):
            processLocalMove(op, document: document)
        case let .updateCommon(op):
            processLocalUpdateCommon(op, document: document)
        case let .updateKind(op):
            processLocalUpdateKind(op, document: document)
        case let .setProperties(op):
            processLocalSetProperties(op, document: document)
        case let .overrideDescendant(op):
            processLocalOverrideDescendant(op, document: document)
        case let .overrideRoot(op):
            processLocalOverrideRoot(op, document: document)
        case .detachRef:
            // Detach is handled by EditableDocument.applyLocalDetachRef() which
            // decomposes it into delete + insert primitives. This path should
            // never be reached in CRDT mode, but returns empty ops defensively.
            []
        case .replaceSubtree:
            // Replace is handled by EditableDocument.applyLocalReplaceSubtree(),
            // which decomposes it into the property and structural primitives both
            // peers already converge on. Defensive for the same reason as detach.
            []
        case let .addVariable(op):
            processLocalSetVariable(name: op.name, variable: op.variable)
        case let .updateVariable(op):
            processLocalSetVariable(name: op.name, variable: op.variable)
        case let .removeVariable(op):
            processLocalRemoveVariable(name: op.name)
        case let .addImport(op):
            processLocalSetImport(alias: op.alias, path: op.path)
        case let .updateImport(op):
            processLocalSetImport(alias: op.alias, path: op.path)
        case let .removeImport(op):
            processLocalRemoveImport(alias: op.alias)
        case let .addThemeAxis(op):
            processLocalSetThemeAxis(name: op.name, options: op.options)
        case let .updateThemeAxis(op):
            processLocalSetThemeAxis(name: op.name, options: op.options)
        case let .removeThemeAxis(op):
            processLocalRemoveThemeAxis(name: op.name)
        }
    }

    /// Applies a remote ``CRDTOperation`` and returns mutations for the flat store.
    ///
    /// Returns `nil` if the operation is a no-op (e.g. editing a tombstoned node,
    /// or a tree move that would create a cycle).
    ///
    /// - Parameters:
    ///   - operation: The remote CRDT operation.
    ///   - document: The current flat store.
    /// - Returns: Mutations to apply, or `nil` if the operation was rejected.
    public func processRemote(operation: CRDTOperation, document: EditableDocument) -> [DocumentMutation]? {
        operationLog.appendRemote(operation)

        switch operation.payload {
        case let .setProperty(p):
            return processRemoteSetProperty(p, timestamp: operation.id, document: document)
        case let .listInsert(p):
            return processRemoteListInsert(p)
        case let .listDelete(p):
            return processRemoteListDelete(p)
        case let .listMove(p):
            return processRemoteListMove(p)
        case let .treeMove(p):
            return processRemoteTreeMove(p, timestamp: operation.id, document: document)
        case let .createNode(p):
            return processRemoteCreateNode(p, timestamp: operation.id)
        case let .deleteNode(p):
            return processRemoteDeleteNode(p, document: document)
        case let .setVariable(p):
            return processRemoteSetVariable(p, timestamp: operation.id)
        case let .removeVariable(p):
            return processRemoteRemoveVariable(p, timestamp: operation.id)
        case let .setImport(p):
            return processRemoteSetImport(p, timestamp: operation.id)
        case let .removeImport(p):
            return processRemoteRemoveImport(p, timestamp: operation.id)
        case let .setThemeAxis(p):
            return processRemoteSetThemeAxis(p, timestamp: operation.id)
        case let .removeThemeAxis(p):
            return processRemoteRemoveThemeAxis(p, timestamp: operation.id)
        }
    }

    /// Returns pending operations that haven't been seen by the given vector clock.
    ///
    /// - Parameter since: The recipient's vector clock state.
    /// - Returns: Operations to send.
    public func pendingOperations(since: VectorClock) -> [CRDTOperation] {
        operationLog.pending(since: since)
    }
}
