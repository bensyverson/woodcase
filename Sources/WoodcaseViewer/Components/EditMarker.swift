//
//  EditMarker.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// A recent edit to one node, as the render's overlay draws it: a box with a tag naming
/// who did it and when.
///
/// Derived entirely from the activity log — identity, node ids, time — which is why the
/// viewer needs no presence protocol and no extra endpoint. When two identities touch
/// one node they share one marker and the tag names them both, because two boxes on the
/// same rect is a rendering bug, not information.
public struct EditMarker: Friendly, Identifiable {
    /// Creates a marker.
    ///
    /// - Parameters:
    ///   - node: The node id the edit touched, which is also the marker's id.
    ///   - identities: Who touched it, in the log's order of first appearance.
    ///   - op: The most recent verb recorded against it.
    ///   - time: When it was last touched.
    public init(node: String, identities: [String], op: ActivityEvent.Kind, time: Date) {
        self.node = node
        self.identities = identities
        self.op = op
        self.time = time
    }

    /// The node id the edit touched.
    public var id: String {
        node
    }

    /// The node id the edit touched.
    public let node: String

    /// Who touched it, in the log's order of first appearance.
    public let identities: [String]

    /// The most recent verb recorded against it.
    public let op: ActivityEvent.Kind

    /// When it was last touched.
    public let time: Date

    /// The color the box is drawn in: the first editor's.
    public var color: ActorColor {
        ActorColor(name: identities.first ?? "")
    }

    /// The markers a run of log events produces, newest edit per node.
    ///
    /// - Parameters:
    ///   - events: The file's events, oldest first.
    ///   - clock: The moment the page is rendered for; only edits inside its recency
    ///     window become markers.
    /// - Returns: One marker per touched node, most recently touched first.
    public static func markers(in events: [ActivityEvent], clock: ViewerClock) -> [EditMarker] {
        var identities: [String: [String]] = [:]
        var latest: [String: (op: ActivityEvent.Kind, time: Date)] = [:]
        var order: [String] = []

        for event in events where clock.isRecent(event.time) {
            for node in event.nodes {
                if identities[node] == nil {
                    identities[node] = []
                    order.append(node)
                }
                if !(identities[node] ?? []).contains(event.identity) {
                    identities[node]?.append(event.identity)
                }
                latest[node] = (event.op, event.time)
            }
        }

        return order.compactMap { node in
            guard let last = latest[node] else { return nil }
            return EditMarker(
                node: node,
                identities: identities[node] ?? [],
                op: last.op,
                time: last.time
            )
        }
        .sorted { $0.time > $1.time }
    }
}
