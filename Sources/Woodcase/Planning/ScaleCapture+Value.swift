//
//  ScaleCapture+Value.swift
//  Woodcase
//

import Foundation

extension ScaleCapture.Entry {
    /// One value of a captured node that a scale multiplies, and how.
    struct Value: Friendly {
        /// How a value's lengths are found and multiplied (``ProportionalScaler``).
        enum Rule: Friendly {
            /// An axis of the plane.
            enum Axis: Friendly {
                /// Across.
                case x
                /// Down.
                case y
            }

            /// One length.
            case length
            /// A length or a list of them: a radius, a padding, a dash.
            case lengths
            /// A `width` or `height`, its sizing mode kept.
            case sizing
            /// A stroke width, uniform or per side.
            case sides
            /// A node's effects.
            case effects
            /// A `metadata.woodcase.shadowSpread` list.
            case shadowSpreads
            /// A `metadata.woodcase.spans` object.
            case spans
            /// A member's coordinate, scaled about the anchor's on this axis.
            case coordinate(Axis)

            /// `value` scaled by this rule.
            ///
            /// - Parameters:
            ///   - value: The value as drawn.
            ///   - scaler: The step's scaler, which notes each variable met.
            ///   - pivot: The anchor in the node's parent's coordinates, for a coordinate.
            /// - Returns: The value to write.
            func apply(to value: AnyCodable, by scaler: inout ProportionalScaler, about pivot: PenPoint) -> AnyCodable {
                switch self {
                case .length: scaler.length(value)
                case .lengths: scaler.lengths(value)
                case .sizing: scaler.sizing(value)
                case .sides: scaler.sides(value)
                case .effects: scaler.effects(value)
                case .shadowSpreads: scaler.shadowSpreads(value)
                case .spans: scaler.spans(value)
                case .coordinate(.x): scaler.coordinate(value, about: pivot.x)
                case .coordinate(.y): scaler.coordinate(value, about: pivot.y)
                }
            }
        }

        /// The property path, as a write names it.
        var path: String

        /// What the node holds there; ``AnyCodable/null`` when unset.
        var held: AnyCodable

        /// What the node is drawn with there: ``held``, or the number an unset value is
        /// drawn at.
        var drawn: AnyCodable

        /// How it scales.
        var rule: Rule
    }
}
