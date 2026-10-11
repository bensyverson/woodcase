//
//  PresenceTracker.swift
//  Woodcase
//

import Foundation

/// Folds activity events and views into a ``Presence`` snapshot.
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

    /// Enters an identity before it has done anything, so it takes its place in the
    /// order of appearance now: an editor's own user, shown from the moment a document
    /// opens. It is seen at `Date.distantPast`, with no files and no changes, until an
    /// event of its own arrives; registering a known identity changes nothing.
    ///
    /// - Parameter name: The identity's `--as` name.
    public mutating func register(_ name: String) {
        guard indexByName[name] == nil else { return }
        add(name, seenAt: .distantPast)
    }

    /// Folds one event in.
    ///
    /// - Parameter event: The event, as read from the log.
    public mutating func record(_ event: ActivityEvent) {
        let index = touch(event.identity, file: event.file, at: event.time)
        identities[index].changes += 1
        fold(event, into: index)
    }

    /// Folds one read in: it sets the reader's ``Presence/Identity/latestView``.
    ///
    /// - Parameter view: The read, from a ``ViewReader`` or a ``PenFileFollower``.
    public mutating func record(_ view: ViewEvent) {
        let index = touch(view.identity, file: view.file, at: view.time)
        if let latest = identities[index].latestView, latest.time > view.time { return }
        identities[index].latestView = Presence.NodeMark(
            nodes: view.nodes, paths: [], revision: view.revision, time: view.time, verb: view.verb
        )
    }

    /// Folds in whatever a ``PenFileFollower`` delivered: the rows of a change, a lone
    /// row, or a read. A restart carries nothing to fold.
    ///
    /// - Parameter event: The follower's event.
    public mutating func record(_ event: PenFileFollower.Event) {
        switch event {
        case let .changed(change):
            for row in change.events {
                record(row)
            }
        case let .activity(row):
            record(row)
        case let .viewed(view):
            record(view)
        case .restarted:
            break
        }
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

    /// Finds or adds an identity, and notes that it was seen at `time` on `file`.
    ///
    /// - Returns: The identity's index.
    private mutating func touch(_ name: String, file: String, at time: Date) -> Int {
        let index = indexByName[name] ?? add(name, seenAt: time)
        identities[index].lastSeen = max(identities[index].lastSeen, time)
        identities[index].files.removeAll { $0 == file }
        identities[index].files.insert(file, at: 0)
        return index
    }

    /// Adds an identity at the end of the order, seen at `time`.
    ///
    /// - Returns: Its index.
    @discardableResult
    private mutating func add(_ name: String, seenAt time: Date) -> Int {
        let index = identities.count
        indexByName[name] = index
        identities.append(Presence.Identity(name: name, order: index, lastSeen: time, changes: 0))
        batches.append(nil)
        return index
    }

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
