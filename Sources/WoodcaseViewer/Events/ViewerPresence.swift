//
//  ViewerPresence.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Who has been editing, and how long ago — the payload of a `presence` event.
///
/// Presence is derived entirely from the activity log. There is no registration, no
/// heartbeat from an agent, nothing to keep in sync: an identity is present because it
/// wrote something, and its age is how long ago that was. An agent that has gone away
/// simply stops getting newer.
///
/// Identities are ordered by **first appearance in the log**, and that order is part of
/// the contract: the page assigns each identity a color by it, so an agent keeps the
/// same color for as long as the log does.
public struct ViewerPresence: Friendly {
    /// Creates a presence snapshot.
    ///
    /// - Parameter identities: The identities, in order of first appearance.
    public init(identities: [Identity]) {
        self.identities = identities
    }

    /// One identity seen in the log.
    public struct Identity: Friendly {
        /// Creates an identity.
        ///
        /// - Parameters:
        ///   - name: The `--as` name it writes under.
        ///   - lastSeen: When it last wrote.
        ///   - events: How many events it has written in the log this viewer has read.
        ///   - files: The ids of the files it has touched, most recent first.
        public init(name: String, lastSeen: Date, events: Int, files: [String]) {
            self.name = name
            self.lastSeen = lastSeen
            self.events = events
            self.files = files
        }

        /// The `--as` name it writes under.
        public let name: String

        /// When it last wrote. Compare against now for the "last seen" age.
        public let lastSeen: Date

        /// How many events it has written in the log this viewer has read.
        public let events: Int

        /// The ids of the files it has touched, most recently touched first.
        public let files: [String]
    }

    /// The identities, in order of first appearance in the log.
    public let identities: [Identity]
}
