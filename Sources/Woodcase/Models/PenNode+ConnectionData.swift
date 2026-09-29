//
//  PenNode+ConnectionData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Connection

    /// Type-specific data for a `connection` node — a connector drawn from an anchor on
    /// one node to an anchor on another.
    ///
    /// ```json
    /// {"type": "connection", "id": "cAB",
    ///  "source": {"path": "rA", "anchor": "right"},
    ///  "target": {"path": "card/title", "anchor": "left"},
    ///  "stroke": "#71717A", "strokeWidth": 2}
    /// ```
    ///
    /// The keys are exactly those Pen's validator accepts on a connection: ``source`` and
    /// ``target``, both required, and the five stroke keys — no fill, no size, no effects.
    /// Pen accepts a connection only at the top level of the document, never inside a
    /// frame or group. A connection has no box of its own: it is drawn from where its two
    /// endpoints are, so its `x`, `y` and rotation play no part in the drawing.
    ///
    /// Pen 1.2.14's validator knows the node, but neither its app nor its headless engine
    /// loads one, so there is no Pen rendering to match. Woodcase draws a straight
    /// segment between the two anchor points, painted by the stroke like a `line` —
    /// no stroke, nothing drawn (see <doc:PenRendering>).
    struct ConnectionData: Friendly, PenStrokable {
        /// Creates a connection payload.
        ///
        /// - Parameters:
        ///   - source: Where the connector starts.
        ///   - target: Where the connector ends.
        ///   - stroke: The stroke's paint; `nil` draws nothing.
        ///   - strokeWidth: The stroke's width.
        ///   - strokeLinecap: How the connector's ends are capped.
        ///   - strokeLinejoin: How corners are joined.
        ///   - strokeAlignment: Where the stroke sits relative to the segment.
        public init(
            source: Endpoint,
            target: Endpoint,
            stroke: PenFills? = nil,
            strokeWidth: PenStrokeWidth? = nil,
            strokeLinecap: PenStrokeCap? = nil,
            strokeLinejoin: PenStrokeJoin? = nil,
            strokeAlignment: PenStrokeAlign? = nil
        ) {
            self.source = source
            self.target = target
            self.stroke = stroke
            self.strokeWidth = strokeWidth
            self.strokeLinecap = strokeLinecap
            self.strokeLinejoin = strokeLinejoin
            self.strokeAlignment = strokeAlignment
        }

        /// Where the connector starts.
        public var source: Endpoint
        /// Where the connector ends.
        public var target: Endpoint
        /// The stroke's paint. A connection with none draws nothing.
        public var stroke: PenFills?
        /// The stroke's width.
        public var strokeWidth: PenStrokeWidth?
        /// How the connector's ends are capped.
        public var strokeLinecap: PenStrokeCap?
        /// How corners are joined.
        public var strokeLinejoin: PenStrokeJoin?
        /// Where the stroke sits relative to the segment.
        public var strokeAlignment: PenStrokeAlign?

        /// The keys a `connection` node writes.
        public enum CodingKeys: String, CodingKey {
            case source, target
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
        }

        // MARK: Endpoint

        /// One end of a connection: a node, and the point on its box the connector meets.
        public struct Endpoint: Friendly {
            /// Creates an endpoint.
            ///
            /// - Parameters:
            ///   - path: The node's id, or a slash-separated path of ids for a node
            ///     inside a component instance (`instance/child`).
            ///   - anchor: The point on the node's box.
            ///   - extras: Keys a file wrote on the endpoint that the model does not claim.
            public init(path: String, anchor: Anchor, extras: PenExtras = PenExtras()) {
                self.path = path
                self.anchor = anchor
                self.extras = extras
            }

            /// The node's id, or a slash-separated path of ids reaching into a
            /// component instance — the same spelling an expanded instance's
            /// descendants are keyed by.
            public var path: String

            /// The point on the node's box the connector meets.
            public var anchor: Anchor

            /// Keys the file wrote on this endpoint that the model does not claim. See ``PenExtras``.
            public var extras = PenExtras()

            /// The keys an endpoint claims; any other key of its object is an extra.
            enum CodingKeys: String, CodingKey, CaseIterable {
                case path, anchor
            }
        }

        // MARK: Anchor

        /// A point on a node's box: its center, or the middle of one of its edges.
        ///
        /// The five spellings, in the order Pen's validator lists them.
        public enum Anchor: String, Friendly, CaseIterable {
            /// The center of the box.
            case center
            /// The middle of the top edge.
            case top
            /// The middle of the left edge.
            case left
            /// The middle of the bottom edge.
            case bottom
            /// The middle of the right edge.
            case right
        }

        // MARK: AnchorPoint

        /// A point on the canvas, in points: where an anchor lands.
        public struct AnchorPoint: Friendly {
            /// Creates a point.
            public init(x: Double, y: Double) {
                self.x = x
                self.y = y
            }

            /// The horizontal coordinate.
            public var x: Double
            /// The vertical coordinate.
            public var y: Double
        }

        // MARK: Segment

        /// The straight run of a connector, from its source's anchor to its target's.
        public struct Segment: Friendly {
            /// Creates a segment.
            public init(from: AnchorPoint, to: AnchorPoint) {
                self.from = from
                self.to = to
            }

            /// Where the connector starts.
            public var from: AnchorPoint
            /// Where the connector ends.
            public var to: AnchorPoint
        }
    }
}
