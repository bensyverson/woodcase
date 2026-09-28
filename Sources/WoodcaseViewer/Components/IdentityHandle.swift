//
//  IdentityHandle.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// An identity written out as text: the `--as` handle a writer typed, or the word
/// `unattributed` for a write made with none.
///
/// ``ActivityEvent/unattributed`` is an empty string, and an empty string written as a
/// name is a hole — `2 active ·  editing`, or a blank column in an activity row beside a
/// `?` disc (issue `JFazoq`). DESIGN.md: "an unattributed write is a real state, not a
/// rendering bug". So every place a name is written as text goes through this, and says
/// so in one shared word — the word ``AvatarView``'s `title` already used. Like the `#id`
/// stand-in for an unnamed node it is faint: it is the absence of a name, spelled.
///
/// ```swift
/// IdentityHandle(event.identity, className: "v-activity-identity")
/// ```
public struct IdentityHandle: HTML {
    /// The word an unattributed writer is written as.
    public static let unattributed = "unattributed"

    /// Creates a handle.
    ///
    /// - Parameters:
    ///   - identity: The identity, possibly ``ActivityEvent/unattributed``.
    ///   - className: The caller's class for the span, which carries its typography.
    public init(_ identity: String, className: String) {
        self.identity = identity
        self.className = className
    }

    /// The identity, possibly empty.
    public let identity: String

    /// The caller's class for the span.
    public let className: String

    /// What the identity reads as.
    ///
    /// - Parameter identity: The identity, possibly ``ActivityEvent/unattributed``.
    /// - Returns: The handle, or ``unattributed`` for an empty one.
    public static func text(_ identity: String) -> String {
        identity == ActivityEvent.unattributed ? unattributed : identity
    }

    public var body: some HTML {
        span(.class(className)) { Self.text(identity) }
            .attributes(.class("is-unattributed"), when: identity == ActivityEvent.unattributed)
    }
}
