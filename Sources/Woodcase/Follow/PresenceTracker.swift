//
//  PresenceTracker.swift
//  Woodcase
//

import Foundation

/// Folds activity events into a ``Presence`` snapshot.
///
/// A value, not an actor: it holds nothing but the running tally, so whoever is already
/// serializing the log owns one and no second lock is needed.
///
/// One change is one **batch**: the events of a transaction share a batch id, and the
/// tracker keeps one ``Presence/NodeMark`` for them — the nodes of every event, the
/// first event's subject first — rather than a mark per event. An event with no batch id
/// stands alone.
public struct PresenceTracker: Friendly {
    /// Creates an empty tracker.
    public init() {}

    /// Folds one event in.
    ///
    /// - Parameter event: The event, as read from the log.
    public mutating func record(_ event: ActivityEvent) {
        let index: Int
        if let known = indexByName[event.identity] {
            index = known
        } else {
            index = identities.count
            indexByName[event.identity] = index
            identities.append(Presence.Identity(
                name: event.identity, order: index, lastSeen: event.time, changes: 0
            ))
            batches.append(nil)
        }

        identities[index].changes += 1
        identities[index].lastSeen = max(identities[index].lastSeen, event.time)
        identities[index].files.removeAll { $0 == event.file }
        identities[index].files.insert(event.file, at: 0)
        fold(event, into: index)
    }

    /// The current snapshot.
    ///
    /// - Returns: The identities, in order of first appearance in the log.
    public func snapshot() -> Presence {
        Presence(identities: identities)
    }

    /// Whether anything has been recorded.
    public var isEmpty: Bool {
        identities.isEmpty
    }

    // MARK: - Private

    private var identities: [Presence.Identity] = []
    private var indexByName: [String: Int] = [:]

    /// The batch id behind each identity's latest mark, so the next event of the same
    /// batch extends it instead of replacing it.
    private var batches: [String?] = []

    /// Updates the identity's latest mark from an event; events naming no node leave it alone.
    private mutating func fold(_ event: ActivityEvent, into index: Int) {
        guard !event.nodes.isEmpty else { return }
        if let batch = event.batch, batch == batches[index], var mark = identities[index].latestChange {
            for (node, path) in zip(event.nodes, Self.paths(of: event)) where !mark.nodes.contains(node) {
                guard mark.nodes.count < Presence.NodeMark.nodeLimit else { break }
                mark.nodes.append(node)
                mark.paths.append(path)
            }
            mark.revision = event.revision
            mark.time = max(mark.time, event.time)
            if mark.op != event.op { mark.op = nil }
            identities[index].latestChange = mark
        } else {
            identities[index].latestChange = Presence.NodeMark(
                nodes: event.nodes,
                paths: Self.paths(of: event),
                revision: event.revision,
                time: event.time,
                op: event.op
            )
        }
        batches[index] = event.batch
    }

    /// An event's paths padded to its nodes, so the two stay index-aligned.
    private static func paths(of event: ActivityEvent) -> [String] {
        event.nodes.indices.map { $0 < event.paths.count ? event.paths[$0] : "" }
    }
}
