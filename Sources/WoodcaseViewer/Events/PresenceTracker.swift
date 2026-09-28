//
//  PresenceTracker.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Folds activity events into a ``ViewerPresence`` snapshot.
///
/// A value, not an actor: it holds nothing but the running tally, so whoever is already
/// serializing the log — the ``ChangeCoordinator`` — owns one and no second lock is
/// needed.
public struct PresenceTracker: Friendly {
    /// Creates an empty tracker.
    public init() {}

    /// What is known about one identity.
    private struct Seen: Friendly {
        var lastSeen: Date
        var events: Int
        var files: [String]
    }

    /// Identities in order of first appearance — the order the page colours by.
    private var order: [String] = []

    /// The tally per identity.
    private var seen: [String: Seen] = [:]

    /// Folds one event in.
    ///
    /// - Parameters:
    ///   - event: The event, as read from the log.
    ///   - fileID: The ``ViewerFile/id`` of the file it names, when the viewer serves it.
    public mutating func record(_ event: ActivityEvent, fileID: String? = nil) {
        guard var existing = seen[event.identity] else {
            order.append(event.identity)
            seen[event.identity] = Seen(
                lastSeen: event.time, events: 1, files: fileID.map { [$0] } ?? []
            )
            return
        }
        existing.events += 1
        existing.lastSeen = max(existing.lastSeen, event.time)
        if let fileID {
            existing.files.removeAll { $0 == fileID }
            existing.files.insert(fileID, at: 0)
        }
        seen[event.identity] = existing
    }

    /// The current snapshot.
    ///
    /// - Returns: The identities, in order of first appearance in the log.
    public func snapshot() -> ViewerPresence {
        ViewerPresence(identities: order.compactMap { name in
            guard let entry = seen[name] else { return nil }
            return ViewerPresence.Identity(
                name: name, lastSeen: entry.lastSeen, events: entry.events, files: entry.files
            )
        })
    }

    /// Whether anything has been recorded.
    public var isEmpty: Bool {
        order.isEmpty
    }
}
