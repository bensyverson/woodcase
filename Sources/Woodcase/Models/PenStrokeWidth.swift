//
//  PenStrokeWidth.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// The width of a node's stroke — either uniform or per-side.
///
/// The .pen 2.17 `strokeWidth` key takes a number, a `"$variable"` reference, or an
/// **object** with a value for each side: `{"top":1,"right":2,"bottom":3,"left":4}`.
/// Sides the object omits carry no stroke.
public enum PenStrokeWidth: Friendly {
    /// One width for the whole outline.
    case uniform(PenValue<Double>)
    /// A width per edge; a `nil` side is not stroked.
    case perSide(Sides)

    /// Decodes either the scalar form or the per-side object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try as a single value (number or "$var")
        if let single = try? container.decode(PenValue<Double>.self) {
            self = .uniform(single)
            return
        }

        // Try as an object with per-side values
        self = try .perSide(container.decode(Sides.self))
    }

    /// Encodes the scalar form as a bare value and the per-side form as an object.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .uniform(value):
            try container.encode(value)
        case let .perSide(sides):
            try container.encode(sides)
        }
    }

    /// A width per edge — the .pen per-side `strokeWidth` object.
    public struct Sides: Friendly {
        /// Creates a set of per-side widths.
        ///
        /// - Parameters:
        ///   - top: The top edge's width; `nil` means no stroke on that edge.
        ///   - right: The right edge's width; `nil` means no stroke on that edge.
        ///   - bottom: The bottom edge's width; `nil` means no stroke on that edge.
        ///   - left: The left edge's width; `nil` means no stroke on that edge.
        ///   - extras: Keys a file wrote on the object that the model does not claim.
        public init(
            top: PenValue<Double>? = nil,
            right: PenValue<Double>? = nil,
            bottom: PenValue<Double>? = nil,
            left: PenValue<Double>? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.top = top
            self.right = right
            self.bottom = bottom
            self.left = left
            self.extras = extras
        }

        /// The top edge's width; `nil` means no stroke on that edge.
        public var top: PenValue<Double>?
        /// The right edge's width; `nil` means no stroke on that edge.
        public var right: PenValue<Double>?
        /// The bottom edge's width; `nil` means no stroke on that edge.
        public var bottom: PenValue<Double>?
        /// The left edge's width; `nil` means no stroke on that edge.
        public var left: PenValue<Double>?

        /// Keys the file wrote on this object that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this object claims; any other key is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case top, right, bottom, left
        }
    }
}
