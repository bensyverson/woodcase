//
//  PenCommentThread+Placement.swift
//  Woodcase
//

import Foundation

public extension PenCommentThread {
    /// Where a thread sits, read from its first message's anchor and the document.
    ///
    /// What decides whether and where a bubble is drawn (Ben's session 12 ruling on the
    /// anchor): a thread on a node goes with the node; a canvas thread sits at its page
    /// point; a thread whose node is gone is not drawn and lists only in the Comments tab,
    /// marked as on a deleted layer, its anchor never rewritten — so undoing the delete
    /// brings the bubble back with nothing else to do.
    enum Placement: String, Friendly, CaseIterable {
        /// On a node the document holds: the anchor's point is in its own coordinates.
        case node
        /// On the empty canvas: the anchor has no node and its point is in page coordinates.
        case canvas
        /// On a node that no longer resolves — deleted, or an instance child a component
        /// edit removed. The anchor still names it, as written.
        case deletedNode
        /// The first message carries an anchor that does not read.
        case unreadable
        /// No anchor: the first message names none, or is gone.
        case unanchored
    }
}
