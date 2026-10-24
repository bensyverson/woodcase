//
//  EditPlanner+SlotIntents.swift
//  Woodcase
//

import Foundation

/// The slot's own menu: Replace Content With, Empty Slot and Reset Slot (Penumbra spec
/// §13.5 rules 2, 5 and 11), each one `children` override of the slot — or, for Reset,
/// its removal.
public extension EditPlanner {
    /// Plans Replace Content With: the slot's whole content replaced by instances of a
    /// component — as many as the content had layers, at least one, unless `count` says
    /// otherwise (Ben's ruling of 2026-10-23).
    ///
    /// The old content's text and other edits do not carry over; in a slot that does not
    /// lay out its children, each new instance takes the `x`/`y` of the layer it
    /// replaces. A slot still showing its default content has it copied into a fill
    /// first (rule 6), so the keys that named it go too. Nothing is refused for its type
    /// (rule 7): the suggested components are a menu, not a rule.
    ///
    /// ```swift
    /// let plan = try EditPlanner.planReplaceSlotContent(slotID: "Filled/List", with: "ItemB", in: document)
    /// plan.placedIDs   // three new Item B instances
    /// ```
    ///
    /// Refused for an id that is not an instance's slot (``EditRefusal/Code/notASlot``),
    /// for a component the document does not define (``EditRefusal/Code/addressNotFound``),
    /// and when the instances would make a component contain itself
    /// (``EditRefusal/Code/wouldCloseComponentLoop``).
    ///
    /// - Parameters:
    ///   - slotID: The slot frame's expanded id.
    ///   - componentID: The component to place.
    ///   - count: How many instances; `nil` keeps the content's layer count. At least one
    ///     is placed either way.
    ///   - document: The document, as it stands.
    /// - Returns: The edit and the new instances' expanded ids.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planReplaceSlotContent(
        slotID: String,
        with componentID: String,
        count: Int? = nil,
        in document: EditableDocument
    ) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        let (refID, slotKey) = try slotSite(slotID, in: session)
        guard document.reusableComponent(componentID) != nil else {
            throw EditRefusal(
                code: .addressNotFound, address: componentID, message: "No component has the id \(componentID)."
            )
        }
        guard let map = session.map(of: refID), let index = map.site(slotKey: slotKey) else {
            throw notASlotRefusal(slotID)
        }
        let old = map.sites[index].contentKeys.compactMap { map.nodes[$0]?.node }
        let free = !SlotMove.laysOut(map.sites[index].frame)
        guard let (site, _) = session.ensureFill(slotKey: slotKey, in: refID) else { throw SlotMove.unreadable(slotID) }

        var fill: [AnyCodable] = []
        var localIDs: [String] = []
        for position in 0 ..< max(1, count ?? old.count) {
            let id = PenID.generate(avoiding: session.taken)
            session.taken.insert(id)
            var common = PenNodeCommon()
            if free, position < old.count {
                common.x = old[position].common.x
                common.y = old[position].common.y
            }
            let instance = PenNode(id: id, common: common, kind: .ref(PenNode.RefData(ref: componentID)))
            do {
                try fill.append(SlotJSON.json(of: instance))
            } catch {
                throw EditRefusal(error, address: slotID, in: document)
            }
            localIDs.append(id)
        }
        session.setFill(fill, of: site)
        return try finishing(session, placing: localIDs, in: slotKey, of: refID, address: slotID)
    }

    /// Plans Empty Slot: the slot left with nothing in it — a fill of no nodes, which is
    /// not the same as its default. A slot showing its default content has it copied
    /// into a fill first, so the keys that named it go too.
    ///
    /// - Parameters:
    ///   - slotID: The slot frame's expanded id.
    ///   - document: The document, as it stands.
    /// - Returns: The edit.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/notASlot`` for an id that is not
    ///   an instance's slot.
    static func planEmptySlot(slotID: String, in document: EditableDocument) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        let (refID, slotKey) = try slotSite(slotID, in: session)
        guard let (site, _) = session.ensureFill(slotKey: slotKey, in: refID) else { throw SlotMove.unreadable(slotID) }
        session.setFill([], of: site)
        return try finishing(session, placing: [], in: slotKey, of: refID, address: slotID)
    }

    /// Plans Reset Slot: the fill removed, so the component's default content shows and
    /// follows the component again. A slot already at its default plans nothing.
    ///
    /// - Parameters:
    ///   - slotID: The slot frame's expanded id.
    ///   - document: The document, as it stands.
    /// - Returns: The edit, empty when the slot has no fill.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/notASlot`` for an id that is not
    ///   an instance's slot.
    static func planResetSlot(slotID: String, in document: EditableDocument) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        let (refID, slotKey) = try slotSite(slotID, in: session)
        guard let map = session.map(of: refID), let index = map.site(slotKey: slotKey) else {
            throw notASlotRefusal(slotID)
        }
        guard map.sites[index].isFilled else { return StructuralEditPlan(operations: []) }
        session.setFill(nil, of: map.sites[index])
        return try finishing(session, placing: [], in: slotKey, of: refID, address: slotID)
    }
}

extension EditPlanner {
    /// The instance and slot key a slot frame's expanded id names.
    ///
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/notASlot`` for anything else, or
    ///   ``EditRefusal/Code/addressNotFound``.
    static func slotSite(_ slotID: String, in session: SlotEditSession) throws(EditRefusal) -> (refID: String, slotKey: String) {
        guard case let .inInstance(refID, key) = try session.place(of: slotID),
              session.map(of: refID)?.site(slotKey: key) != nil
        else { throw notASlotRefusal(slotID) }
        return (refID, key)
    }

    /// The refusal for a slot intent aimed at a node that is not a slot.
    static func notASlotRefusal(_ id: String) -> EditRefusal {
        EditRefusal(code: .notASlot, address: id, message: "\(id) is not a slot of an instance.")
    }
}
