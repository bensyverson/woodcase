//
//  PenNode+ConnectionStyle.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData {
    /// A connection's routing and its two arrowheads: everything beyond its endpoints and
    /// stroke that decides what it draws.
    struct Style: Friendly {
        /// Creates a style.
        ///
        /// - Parameters:
        ///   - routing: How the connection runs between its anchors.
        ///   - startArrowhead: What it draws at its source end.
        ///   - endArrowhead: What it draws at its target end.
        public init(routing: Routing, startArrowhead: Arrowhead, endArrowhead: Arrowhead) {
            self.routing = routing
            self.startArrowhead = startArrowhead
            self.endArrowhead = endArrowhead
        }

        /// How the connection runs between its anchors.
        public var routing: Routing
        /// What it draws at its source end.
        public var startArrowhead: Arrowhead
        /// What it draws at its target end.
        public var endArrowhead: Arrowhead

        /// A connection with no keys: straight, with no arrowheads — how every file drew
        /// before the keys existed, and still does.
        public static let plain = Style(routing: .straight, startArrowhead: .none, endArrowhead: .none)

        /// What an editor writes on a connector it creates: elbow routing and an arrowhead
        /// at the target end (Penumbra spec §11.2). A file is never read with it; an
        /// absent key is ``plain``'s.
        public static let newConnector = Style(routing: .elbow, startArrowhead: .none, endArrowhead: .triangle)

        /// How far an elbow runs out from a box before it turns: ``Route/elbowMargin``, or
        /// more when an arrowhead is longer, so the run an arrowhead sits on always holds
        /// it with 8 points of line to spare.
        ///
        /// - Parameter strokeWidth: The stroke's width, which sizes the arrowheads.
        /// - Returns: The margin, in points.
        public func elbowMargin(strokeWidth: Double) -> Double {
            let headed = [startArrowhead, endArrowhead].contains { $0 != .none }
            guard headed, strokeWidth > 0 else { return Route.elbowMargin }
            return max(Route.elbowMargin, Arrowhead.length(forStrokeWidth: strokeWidth) + 8)
        }
    }
}

public extension PenNode {
    /// The connection's routing and arrowheads, or `nil` for a node that is not a
    /// connection.
    ///
    /// Read from ``PenMetadata/WoodcaseKey/routing``, ``PenMetadata/WoodcaseKey/startArrowhead``
    /// and ``PenMetadata/WoodcaseKey/endArrowhead``; each absent key, or one whose value is
    /// not a spelling Woodcase knows, takes ``PenNode/ConnectionData/Style/plain``'s value —
    /// lint's `connection-style-ignored` names the latter.
    var connectionStyle: ConnectionData.Style? {
        guard case .connection = kind else { return nil }
        let metadata = common.metadata
        func spelling(_ key: PenMetadata.WoodcaseKey) -> String? {
            guard case let .string(text)? = metadata?[woodcase: key] else { return nil }
            return text
        }
        let plain = ConnectionData.Style.plain
        return ConnectionData.Style(
            routing: spelling(.routing).flatMap(ConnectionData.Routing.init(rawValue:)) ?? plain.routing,
            startArrowhead: spelling(.startArrowhead).flatMap(ConnectionData.Arrowhead.init(rawValue:))
                ?? plain.startArrowhead,
            endArrowhead: spelling(.endArrowhead).flatMap(ConnectionData.Arrowhead.init(rawValue:))
                ?? plain.endArrowhead
        )
    }
}
