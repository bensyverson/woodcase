//
//  PenCommentThread+Anchor.swift
//  Woodcase
//

import Foundation

public extension PenCommentThread {
    /// What a thread is about: a point on a node, or on the empty canvas.
    ///
    /// Read from the first message's `woodcase.anchor`, written as
    /// `{"node": "<id>", "x": <number>, "y": <number>}` (Ben's session 12 ruling): the
    /// point in the node's own coordinates, in points from its top-left corner, so the
    /// bubble moves and rotates with the node. `node` is an id, or an expanded id path
    /// (`instance/child`) for something inside a component instance. Without `node`, `x`
    /// and `y` are page coordinates: a comment on the empty canvas. A value of another
    /// shape reads as ``PenCommentThread/Placement/unreadable`` rather than as no anchor.
    struct Anchor: Friendly {
        /// The id of the node the thread is about, or `nil` for a canvas comment.
        public var node: String?

        /// The point's horizontal offset: from the node's left edge, or on the page.
        public var x: Double?

        /// The point's vertical offset: from the node's top edge, or on the page.
        public var y: Double?

        /// Creates an anchor.
        ///
        /// - Parameters:
        ///   - node: The node's id or expanded id path; `nil` for a canvas comment.
        ///   - x: The point's horizontal offset.
        ///   - y: The point's vertical offset.
        public init(node: String?, x: Double? = nil, y: Double? = nil) {
            self.node = node
            self.x = x
            self.y = y
        }

        /// Reads an anchor as a file writes it.
        ///
        /// - Parameter value: The value of `woodcase.anchor`.
        /// - Returns: The anchor, or `nil` unless `value` is an object that names a node by
        ///   a string `node` — `x` and `y` then read when they are numbers — or that has no
        ///   `node` and numbers for both `x` and `y`.
        public init?(_ value: AnyCodable) {
            guard case let .dictionary(object) = value else { return nil }
            func number(_ key: String) -> Double? {
                switch object[key] {
                case let .int(whole)?: Double(whole)
                case let .double(fraction)? where fraction.isFinite: fraction
                default: nil
                }
            }
            switch object["node"] {
            case let .string(node)?:
                self.init(node: node, x: number("x"), y: number("y"))
            case nil:
                guard let x = number("x"), let y = number("y") else { return nil }
                self.init(node: nil, x: x, y: y)
            default:
                return nil
            }
        }

        /// The anchor as `woodcase.anchor` writes it: `node` only when there is one, and a
        /// whole-number coordinate as an integer, so the file reads `12` rather than `12.0`.
        public var value: AnyCodable {
            func number(_ value: Double) -> AnyCodable {
                value.rounded() == value && abs(value) < 1e15 ? .int(Int(value)) : .double(value)
            }
            var object: [String: AnyCodable] = [:]
            if let node { object["node"] = .string(node) }
            if let x { object["x"] = number(x) }
            if let y { object["y"] = number(y) }
            return .dictionary(object)
        }
    }
}
