//
//  SlotOrigin.swift
//  Woodcase
//

import Foundation

/// A node a structural edit takes from where it is: a stored node, or slot content.
enum SlotOrigin: Equatable {
    /// A stored node outside any instance.
    case document(String)

    /// A node in an instance's slot content, at any depth of it.
    case content(refID: String, key: String)

    /// Whether the node is stored.
    var isStored: Bool {
        if case .document = self { return true }
        return false
    }

    /// Resolves a node an editor names.
    ///
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/insideInstance`` for a node of
    ///   an instance outside its slots' content, or ``EditRefusal/Code/addressNotFound``.
    init(_ id: String, in session: SlotEditSession) throws(EditRefusal) {
        switch try session.place(of: id) {
        case let .stored(stored):
            self = try .document(EditPlanner.restructuredID(stored, in: session.document))
        case let .inInstance(refID, key):
            guard session.map(of: refID)?.nodes[key]?.siteIndex != nil else {
                throw EditPlanner.outsideSlotsRefusal(id)
            }
            self = .content(refID: refID, key: key)
        }
    }

    /// The origins with each repeat, and each node inside another, left out — it goes
    /// with the one that holds it.
    static func topMost(_ origins: [SlotOrigin], in session: SlotEditSession) -> [SlotOrigin] {
        var unique: [SlotOrigin] = []
        for origin in origins where !unique.contains(origin) {
            unique.append(origin)
        }
        return unique.filter { origin in
            !unique.contains { other in other != origin && origin.isInside(other, in: session) }
        }
    }

    /// Whether this node is inside another.
    private func isInside(_ other: SlotOrigin, in session: SlotEditSession) -> Bool {
        switch (self, other) {
        case let (.document(id), .document(outer)):
            session.document.isDescendant(id, of: outer)
        case let (.content(refID, _), .document(outer)):
            refID == outer || session.document.isDescendant(refID, of: outer)
        case let (.content(refID, key), .content(outerRef, outerKey)):
            refID == outerRef && session.map(of: refID)?.key(key, isAtOrInside: outerKey) == true
        case (.document, .content):
            false
        }
    }
}
