//
//  PenNode+ConnectionRouting.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData {
    /// How a connection runs between its two anchors.
    ///
    /// Stored in `metadata.woodcase.routing` and written at `kind.routing`
    /// (``PenMetadata/WoodcaseKey/routing``): Pen's format has no routing, and Pen drops a
    /// connection when it opens a file, so this is Woodcase's own extension (Penumbra
    /// ruling R11). Absent, or a spelling Woodcase does not know, is ``straight`` — how
    /// every connection was drawn before the key existed.
    enum Routing: String, Friendly, CaseIterable {
        /// One straight segment from anchor to anchor.
        case straight
        /// An orthogonal route that leaves the source's side and enters the target's
        /// perpendicular to them (``PenNode/ConnectionData/route(in:routing:)``).
        case elbow
    }
}
