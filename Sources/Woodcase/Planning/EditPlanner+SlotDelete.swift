//
//  EditPlanner+SlotDelete.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans a delete that reaches slot content, or `nil` when none of the ids is in a
    /// slot — the delete is then the document's own.
    ///
    /// Each slot loses its nodes in one rewrite of its fill; a slot showing its default
    /// content has that content copied into a fill first. Stored nodes delete as
    /// ``planDelete(nodeIDs:in:)`` deletes them, and the connectors attached to anything
    /// the delete removes go with it.
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes, by stored or expanded id.
    ///   - document: The document, as it stands.
    /// - Returns: The plan, or `nil`.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planSlotDelete(nodeIDs: [String], in document: EditableDocument) throws(EditRefusal) -> DeletionPlan? {
        let session = SlotEditSession(document: document)
        var origins: [SlotOrigin] = []
        for id in nodeIDs {
            guard case .inInstance = try session.place(of: id) else {
                try origins.append(SlotOrigin(id, in: session))
                continue
            }
            // Inside an instance only slot content is deletable; anything else is the
            // document's own refusal, as before slots were.
            guard let origin = try? SlotOrigin(id, in: session) else { return nil }
            origins.append(origin)
        }
        guard origins.contains(where: { !$0.isStored }) else { return nil }
        let topMost = SlotOrigin.topMost(origins, in: session)

        var stored: [String] = []
        var removed: Set<String> = []
        var removedPaths: Set<String> = []
        var named: [String] = []
        for origin in topMost {
            switch origin {
            case let .document(id):
                stored.append(id)
                removed.formUnion(document.descendantIDs(of: id))
                named.append(id)
            case let .content(refID, key):
                guard let map = session.map(of: refID) else { continue }
                named.append(map.expandedID(of: key))
                // Ends name slot content by its id path, as it stands before any copy of
                // the default content renames it.
                let separator = String(NodeAddress.separator)
                removedPaths.formUnion(map.nodes.keys.filter { map.key($0, isAtOrInside: key) }.map { refID + separator + $0 })
                let removedIDs = try deleteContent(key, of: refID, in: session)
                let base = session.contentBase(refID: refID, slotKey: map.sites[map.nodes[key]?.siteIndex ?? 0].slotKey)
                removedPaths.formUnion(removedIDs.map { base + $0 })
            }
        }
        let attached = Set(connectorIDs(attachedTo: removed, in: document) + connectorIDs(endingIn: removedPaths, in: document))
        let connectors = document.nodeIDsInDocumentOrder().filter(attached.contains)
        session.deletedConnectorIDs = attached
        let deletes = (connectors + stored).map { EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: $0)) }
        let overrides = session.writeOperations()
        try validating(overrides, address: nodeIDs.first ?? "", in: document)
        return DeletionPlan(operations: deletes + overrides, nodeIDs: named, connectorIDs: connectors)
    }

    /// Takes one node of slot content out of its fill.
    ///
    /// - Returns: The ids of every node it held, as the fill writes them.
    private static func deleteContent(
        _ key: String, of refID: String, in session: SlotEditSession
    ) throws(EditRefusal) -> [String] {
        guard let before = session.map(of: refID), let siteIndex = before.nodes[key]?.siteIndex else {
            throw outsideSlotsRefusal(key)
        }
        let slotKey = before.sites[siteIndex].slotKey
        guard let (site, fill) = session.ensureFill(slotKey: session.current(slotKey, in: refID), in: refID),
              let localID = session.map(of: refID)?.nodes[session.current(key, in: refID)]?.localID
        else { throw SlotMove.unreadable(key) }
        var list = fill
        guard let taken = SlotJSON.remove(localID, from: &list) else { throw SlotMove.unreadable(key) }
        session.setFill(list, of: site)
        return SlotJSON.allIDs(in: [taken])
    }

    /// The connectors with an end on one of some id paths, or inside one.
    private static func connectorIDs(endingIn paths: Set<String>, in document: EditableDocument) -> [String] {
        guard !paths.isEmpty else { return [] }
        let separator = String(NodeAddress.separator)
        return document.nodes.compactMap { id, node in
            guard case let .connection(data) = node.kind else { return nil }
            let touches = [data.source.path, data.target.path].contains { end in
                paths.contains(end) || paths.contains { end.hasPrefix($0 + separator) }
            }
            return touches ? id : nil
        }
    }
}
