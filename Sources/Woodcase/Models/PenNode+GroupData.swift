//
//  PenNode+GroupData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Group

    /// A transparent container: `Entity + children + effects` only.
    ///
    /// Pen 2.17 removed a group's flex-container properties (`layout`, `gap`,
    /// `padding`, `justifyContent`, `alignItems`, `width`, `height`) — a group
    /// no longer lays itself out. Its children are always positioned at their
    /// own explicit x/y, and its rect is their union measured from the group's
    /// own origin; see ``PenLayoutEngine``. Having no box of its own, a group's
    /// `x`/`y` anchors that coordinate system rather than marking the corner of
    /// a bounding box, so its rect is never expanded for rotation and the
    /// renderer pivots it at that anchor. ``PenLegacyMigrator`` drops the
    /// removed keys from an older document.
    struct GroupData: Friendly {
        public init(
            effects: PenEffects? = nil,
            blendMode: PenBlendMode? = nil,
            children: [PenNode]? = nil
        ) {
            self.effects = effects
            self.blendMode = blendMode
            self.children = children
        }

        public var effects: PenEffects?
        public var blendMode: PenBlendMode?
        public var children: [PenNode]?

        public enum CodingKeys: String, CodingKey {
            case effects = "effect", blendMode, children
        }
    }
}
