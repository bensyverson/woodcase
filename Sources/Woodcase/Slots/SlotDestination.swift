//
//  SlotDestination.swift
//  Woodcase
//

import Foundation

/// Where a structural edit puts nodes: a stored parent, or a slot of an instance.
enum SlotDestination: Equatable {
    /// A stored parent outside any instance, or the canvas for `nil`.
    case document(String?)

    /// An instance's slot: the slot frame itself, or a container in its content.
    ///
    /// - Parameters:
    ///   - refID: The outermost instance.
    ///   - slotKey: The slot frame's key.
    ///   - containerKey: The key of the container in the slot's content, or `nil` for
    ///     the slot frame.
    case slot(refID: String, slotKey: String, containerKey: String?)

    /// Resolves a parent an editor names.
    ///
    /// - Parameters:
    ///   - parentID: A stored id, an expanded id, or `nil` for the canvas.
    ///   - session: The plan's session.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/insideInstance`` for anything
    ///   inside an instance that is neither a slot nor a container in one — an instance's
    ///   root included — or ``EditRefusal/Code/addressNotFound``.
    init(_ parentID: String?, in session: SlotEditSession) throws(EditRefusal) {
        guard let parentID else {
            self = .document(nil)
            return
        }
        switch try session.place(of: parentID) {
        case let .stored(id):
            if case .ref? = session.document.node(id: id)?.kind {
                throw EditPlanner.outsideSlotsRefusal(parentID)
            }
            self = .document(id)
        case let .inInstance(refID, key):
            guard let map = session.map(of: refID) else { throw EditPlanner.outsideSlotsRefusal(parentID) }
            if map.site(slotKey: key) != nil {
                self = .slot(refID: refID, slotKey: key, containerKey: nil)
                return
            }
            guard let node = map.nodes[key], let site = node.siteIndex, Self.isContainer(node.node) else {
                throw EditPlanner.outsideSlotsRefusal(parentID)
            }
            self = .slot(refID: refID, slotKey: map.sites[site].slotKey, containerKey: key)
        }
    }

    /// Whether a node takes children: a frame or a group.
    static func isContainer(_ node: PenNode) -> Bool {
        switch node.kind {
        case .frame, .group: true
        default: false
        }
    }

    /// Refuses moving a node into itself: an instance, or a node holding one, into one of
    /// that instance's slots; slot content into itself or a slot inside it.
    ///
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/wouldCreateCycle``.
    func refuseCycles(moving origins: [SlotOrigin], in session: SlotEditSession) throws(EditRefusal) {
        guard case let .slot(refID, slotKey, containerKey) = self else { return }
        let target = containerKey ?? slotKey
        let targetID = session.map(of: refID)?.expandedID(of: target) ?? target
        for origin in origins {
            switch origin {
            case let .document(id):
                guard id == refID || session.document.isDescendant(refID, of: id) else { continue }
                throw Self.cycle(id, into: targetID)
            case let .content(originRef, key):
                guard originRef == refID, session.map(of: refID)?.key(target, isAtOrInside: key) == true else { continue }
                throw Self.cycle(session.map(of: refID)?.expandedID(of: key) ?? key, into: targetID)
            }
        }
    }

    /// The refusal for a node moved into itself.
    private static func cycle(_ nodeID: String, into targetID: String) -> EditRefusal {
        EditRefusal(
            code: .wouldCreateCycle,
            address: nodeID,
            message: "\(nodeID) can't move into \(targetID), which is inside it.",
            detail: .wouldCreateCycle(nodeID: nodeID, targetParentID: targetID)
        )
    }
}

extension EditPlanner {
    /// The refusal for a node inside an instance outside its slots, or a target there.
    static func outsideSlotsRefusal(_ id: String) -> EditRefusal {
        EditRefusal(
            code: .insideInstance,
            address: id,
            message: "\(id) is inside a component instance, outside its slots, whose nodes are its component's; "
                + "edit the component itself, or detach the instance."
        )
    }
}
