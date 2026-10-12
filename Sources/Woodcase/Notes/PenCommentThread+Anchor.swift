//
//  PenCommentThread+Anchor.swift
//  Woodcase
//

import Foundation

public extension PenCommentThread {
    /// What a thread is about: a node, and the point on it the bubble marks.
    ///
    /// Read from the first message's `woodcase.anchor`, written as
    /// `{"node": "<id>", "x": <number>, "y": <number>}` — the point in the node's own
    /// coordinates. Decision 8 names the node and the point but not their spelling, so
    /// this is the reading Woodcase takes until one is ruled; a value of another shape
    /// reads as ``PenCommentThread/hasUnreadableAnchor`` rather than as no anchor.
    struct Anchor: Friendly {
        /// The id of the node the thread is about.
        public var node: String?

        /// The point's horizontal offset in the node, in points.
        public var x: Double?

        /// The point's vertical offset in the node, in points.
        public var y: Double?

        /// Creates an anchor.
        ///
        /// - Parameters:
        ///   - node: The node's id.
        ///   - x: The point's horizontal offset in the node.
        ///   - y: The point's vertical offset in the node.
        public init(node: String?, x: Double? = nil, y: Double? = nil) {
            self.node = node
            self.x = x
            self.y = y
        }

        /// Reads an anchor as a file writes it.
        ///
        /// - Parameter value: The value of `woodcase.anchor`.
        /// - Returns: The anchor, or `nil` unless `value` is an object naming a node by a
        ///   string `node`; `x` and `y` read when they are numbers.
        public init?(_ value: AnyCodable) {
            guard case let .dictionary(object) = value, case let .string(node)? = object["node"] else {
                return nil
            }
            func number(_ key: String) -> Double? {
                switch object[key] {
                case let .int(whole)?: Double(whole)
                case let .double(fraction)? where fraction.isFinite: fraction
                default: nil
                }
            }
            self.init(node: node, x: number("x"), y: number("y"))
        }
    }
}
