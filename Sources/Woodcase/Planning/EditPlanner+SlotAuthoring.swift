//
//  EditPlanner+SlotAuthoring.swift
//  Woodcase
//

import Foundation

/// Making a frame in a component a slot, editing what it suggests, and removing it
/// (Penumbra spec §13.5 rules 9–10).
public extension EditPlanner {
    /// Plans Make Slot: `slot: []` on a frame inside a component, so its instances can
    /// fill it. A frame that is already a slot plans nothing.
    ///
    /// Refused (``EditRefusal/Code/slotNotAllowed``) for a node that is not a frame, a
    /// frame outside every component, where a slot means nothing, and a component's own
    /// frame, which every instance needs as the part that selects it.
    ///
    /// - Parameters:
    ///   - frameID: The frame's stored id.
    ///   - document: The document, as it stands.
    /// - Returns: The edit, empty when the frame is a slot already.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planMakeSlot(frameID: String, in document: EditableDocument) throws(EditRefusal) -> [EditOperation] {
        guard let node = document.node(id: frameID), case let .frame(data) = node.kind,
              node.common.reusable != true,
              document.ancestors(of: frameID).contains(where: { document.node(id: $0)?.common.reusable == true })
        else {
            throw EditRefusal(
                code: .slotNotAllowed, address: frameID,
                message: "\(frameID) can't be a slot: only a frame inside a component, not the component's own frame, can."
            )
        }
        guard data.slot == nil else { return [] }
        return try slotWrite(.array([]), on: frameID, in: document)
    }

    /// Plans an edit of a slot's suggested components: the list, in the order every slot
    /// menu shows it. Any component id is taken, a missing one too — the list suggests,
    /// it never restricts (rule 7) — and copies of the frame carry it.
    ///
    /// - Parameters:
    ///   - componentIDs: The suggested components, in order.
    ///   - frameID: The slot frame's stored id, in its component.
    ///   - document: The document, as it stands.
    /// - Returns: The edit.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/notASlot`` for a frame that is
    ///   not a slot.
    static func planSuggestedComponents(
        _ componentIDs: [String],
        frameID: String,
        in document: EditableDocument
    ) throws(EditRefusal) -> [EditOperation] {
        try requireSlotFrame(frameID, in: document)
        return try slotWrite(.array(componentIDs.map(AnyCodable.string)), on: frameID, in: document)
    }

    /// Plans Remove Slot: the frame stops being a slot, and every fill of it in this
    /// document is removed in the same edit — at any depth: an instance's, a nested
    /// instance's, and one inside another instance's fill. Instances in other documents
    /// keep their fills in the file.
    ///
    /// - Parameters:
    ///   - frameID: The slot frame's stored id, in its component.
    ///   - document: The document, as it stands.
    /// - Returns: The edits and the instances whose fills they clear, which an editor
    ///   names before it goes ahead.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/notASlot`` for a frame that is
    ///   not a slot.
    static func planRemoveSlot(frameID: String, in document: EditableDocument) throws(EditRefusal) -> SlotRemovalPlan {
        try requireSlotFrame(frameID, in: document)
        let session = SlotEditSession(document: document)
        var filled: [String] = []
        let instances = document.nodes.compactMap { id, node -> String? in
            if case .ref = node.kind { return id }
            return nil
        }
        for refID in instances.sorted() {
            guard let map = session.map(of: refID) else { continue }
            // Deepest first, so a fill inside another is cleared before the one holding it.
            for site in map.sites.reversed() where site.componentSlotID == frameID && session.fill(of: site) != nil {
                filled.append(site.instanceRootID)
                session.setFill(nil, of: site)
            }
        }
        let operations = try slotWrite(.null, on: frameID, in: document) + session.writeOperations()
        try validating(operations, address: frameID, in: document)
        return SlotRemovalPlan(operations: operations, filledInstanceIDs: filled.sorted())
    }
}

extension EditPlanner {
    /// Refuses a frame that is not a slot.
    private static func requireSlotFrame(_ frameID: String, in document: EditableDocument) throws(EditRefusal) {
        guard case let .frame(data)? = document.node(id: frameID)?.kind, data.slot != nil else {
            throw notASlotRefusal(frameID)
        }
    }

    /// The write of a frame's `slot` list, checked.
    private static func slotWrite(_ value: AnyCodable, on frameID: String, in document: EditableDocument) throws(EditRefusal) -> [EditOperation] {
        let operations: [EditOperation] = [.setProperties(EditOperation.SetProperties(
            nodeID: frameID, properties: [NodePropertyCodec.kindPrefix + "slot": value]
        ))]
        try validating(operations, address: frameID, in: document)
        return operations
    }
}
