//
//  PenNode+Locked.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// Whether the node is locked: its ``PenMetadata/WoodcaseKey/locked`` is the boolean
    /// `true`. Anything else — no key, `false`, or a value of another type — is unlocked.
    ///
    /// An editor neither hits nor selects a locked node on the canvas, nor anything inside
    /// it, but still lists it in its layers (Penumbra spec §14). The lock is an editor's
    /// convention only: renderers and code generation ignore it, and Pen keeps the key on
    /// save.
    var isLocked: Bool {
        common.metadata?[woodcase: .locked] == .bool(true)
    }
}
