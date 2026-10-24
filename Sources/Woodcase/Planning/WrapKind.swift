//
//  WrapKind.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner/planGroup(nodeIDs:kind:named:in:layout:)`` wraps its members in.
public enum WrapKind: String, Friendly, CaseIterable {
    /// A group: no box of its own, its rect the union of its children's (Group, ⌘G).
    case group

    /// A frame that does not lay out its children (`layout: none`), sized to the
    /// members' union (Frame Selection, ⌥⌘G).
    case frame
}
