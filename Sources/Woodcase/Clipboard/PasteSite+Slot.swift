//
//  PasteSite+Slot.swift
//  Woodcase
//

import Foundation

extension PasteSite {
    /// An instance's slot a paste lands in: the copies join its fill, written by
    /// ``EditPlanner/planInsert(_:into:at:in:)`` as one `children` override of the slot.
    struct SlotParent: Friendly {
        /// The outermost instance, whose `descendants` holds the fill.
        var refID: String
    }

    /// A site inside an instance's slot — a slot frame or a container in its content
    /// (``PasteTarget/inside(containerID:)``) — or `nil` for an id the document stores.
    ///
    /// - Parameters:
    ///   - id: The expanded id the target names.
    ///   - document: The target document.
    /// - Throws: ``PasteError/targetNotFound(id:)`` for an id naming nothing,
    ///   ``PasteError/notAContainer(id:)`` for slot content that holds no children, and
    ///   ``PasteError/slotRefused(_:)`` for a node of an instance outside its slots.
    static func inSlot(inside id: String, in document: EditableDocument) throws -> PasteSite? {
        guard let (map, key) = try instanceNode(id, in: document) else { return nil }
        guard let node = map.nodes[key]?.node else { throw PasteError.targetNotFound(id: id) }
        if map.site(slotKey: key) == nil {
            guard map.nodes[key]?.siteIndex != nil else {
                throw PasteError.slotRefused(EditPlanner.outsideSlotsRefusal(id))
            }
            guard isContainer(node) else { throw PasteError.notAContainer(id: id) }
        }
        let container = map.expandedID(of: key)
        return PasteSite(
            parentID: container, index: nil, arrangement: isStack(node) ? .flow : .container(id: container),
            slot: SlotParent(refID: map.refID)
        )
    }

    /// A site right after a node of an instance's slot content
    /// (``PasteTarget/after(siblingID:)``), or `nil` for an id the document stores.
    ///
    /// - Throws: ``PasteError/targetNotFound(id:)`` for an id naming nothing and
    ///   ``PasteError/slotRefused(_:)`` for a node of an instance outside its slots.
    static func inSlot(after id: String, in document: EditableDocument) throws -> PasteSite? {
        guard let (map, key) = try instanceNode(id, in: document) else { return nil }
        guard let entry = map.nodes[key], entry.siteIndex != nil, let parentKey = entry.parentKey,
              let parent = map.nodes[parentKey]
        else { throw PasteError.slotRefused(EditPlanner.outsideSlotsRefusal(id)) }
        let index = (parent.node.kind.inlineChildren.firstIndex { $0.id == entry.node.id } ?? 0) + 1
        let arrangement: Arrangement = isStack(parent.node)
            ? .flow : .beside(id: map.expandedID(of: key), gap: PenClip.besideGap)
        return PasteSite(
            parentID: map.expandedID(of: parentKey), index: index, arrangement: arrangement,
            slot: SlotParent(refID: map.refID)
        )
    }

    /// The instance map and key of a node drawn inside an instance, or `nil` for an id
    /// the document stores.
    ///
    /// - Throws: ``PasteError/targetNotFound(id:)`` for an id naming nothing.
    private static func instanceNode(_ id: String, in document: EditableDocument) throws -> (SlotMap, String)? {
        guard document.nodes[id] == nil else { return nil }
        let session = SlotEditSession(document: document)
        let place: SlotEditSession.Place
        do {
            place = try session.place(of: id)
        } catch {
            throw PasteError.targetNotFound(id: id)
        }
        switch place {
        case .stored:
            return nil
        case let .inInstance(refID, key):
            guard let map = session.map(of: refID) else {
                throw PasteError.slotRefused(EditPlanner.outsideSlotsRefusal(id))
            }
            return (map, key)
        }
    }
}
