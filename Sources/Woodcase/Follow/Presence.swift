//
//  Presence.swift
//  Woodcase
//

/// Who has been editing a project, and which node each of them touched last.
///
/// Derived entirely from the activity log: an identity is present because it wrote
/// something, and its age is how long ago that was. Nothing registers and nothing sends
/// a heartbeat. Build one by folding events into a ``PresenceTracker``.
///
/// Identities are ordered by **first appearance** in the log, and the order is part of
/// the contract: a UI colors each identity by it, so an agent keeps its color for as long
/// as the log does.
public struct Presence: Friendly {
    /// Creates a snapshot.
    ///
    /// - Parameter identities: The identities, in order of first appearance.
    public init(identities: [Identity] = []) {
        self.identities = identities
    }

    /// The identities, in order of first appearance in the log.
    public var identities: [Identity]
}
