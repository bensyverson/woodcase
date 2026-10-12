//
//  PenPostItExpansion+Shape.swift
//  Woodcase
//

import Foundation

public extension PenPostItExpansion {
    /// A shape part: a rounded rectangle, an ellipse or a check mark, with an optional fill,
    /// a hairline, and outer shadows.
    struct Shape: Friendly {
        /// The outline.
        public var form: Form
        /// The fill, or `nil` for none.
        public var fill: PenHexColor?
        /// The edge, drawn inside the outline — or, for a ``Form/checkMark``, the mark's
        /// stroke, centered on its path with round ends — or `nil` for none.
        public var hairline: Hairline?
        /// The outer shadows, nearest first.
        public var shadows: [Shadow]

        /// Creates a shape.
        ///
        /// - Parameters:
        ///   - form: The outline.
        ///   - fill: The fill.
        ///   - hairline: The edge inside the outline.
        ///   - shadows: The outer shadows.
        public init(form: Form, fill: PenHexColor?, hairline: Hairline? = nil, shadows: [Shadow] = []) {
            self.form = form
            self.fill = fill
            self.hairline = hairline
            self.shadows = shadows
        }

        /// A shape's outline.
        public enum Form: Friendly {
            /// A rectangle with one radius on every corner.
            case roundedRect(cornerRadius: Double)
            /// The ellipse inscribed in the frame.
            case ellipse
            /// A check mark stroked across the frame: an open path, never filled.
            case checkMark
        }

        /// The check mark's path, in a 12 × 12 viewBox mapped onto the part's frame.
        static let checkMarkGeometry = "M3.2 6.3 L5.3 8.4 L8.9 3.8"

        /// The viewBox ``checkMarkGeometry`` is drawn in.
        static let checkMarkViewBox = PenViewBox(x: 0, y: 0, width: 12, height: 12)

        /// The shape as a node a renderer already draws: a `rectangle`, an `ellipse` or a
        /// `path` with the frame's size, a solid fill, a stroke — inner for a closed form,
        /// centered with round caps and joins for the check mark — and outer shadow effects.
        ///
        /// Drawing it at `frame` through the renderer's own node path draws the part with
        /// the renderer's own shadow and stroke code, so two renderers agree on the part
        /// wherever they already agree on nodes.
        ///
        /// - Parameters:
        ///   - id: The node's id, unique among the parts drawn together.
        ///   - frame: The part's frame; the node takes its size.
        /// - Returns: The node.
        public func node(id: String, frame: PenRect) -> PenNode {
            let fills = fill.map { PenFills.single(.shorthand($0.hex)) }
            let stroke = hairline.map { PenFills.single(.shorthand($0.color.hex)) }
            let strokeWidth = hairline.map { PenStrokeWidth.uniform(.literal($0.width)) }
            let alignment: PenStrokeAlign? = hairline == nil ? nil : .inner
            let effects: PenEffects? = shadows.isEmpty ? nil : .multiple(shadows.map(\.effect))
            let width = PenSizing.fixed(frame.width)
            let height = PenSizing.fixed(frame.height)
            let kind: PenNode.Kind = switch form {
            case let .roundedRect(radius):
                .rectangle(PenNode.RectangleData(
                    width: width, height: height, cornerRadius: .uniform(.literal(radius)), fills: fills,
                    stroke: stroke, strokeWidth: strokeWidth, strokeAlignment: alignment, effects: effects
                ))
            case .ellipse:
                .ellipse(PenNode.EllipseData(
                    width: width, height: height, fills: fills,
                    stroke: stroke, strokeWidth: strokeWidth, strokeAlignment: alignment, effects: effects
                ))
            case .checkMark:
                .path(PenNode.PathData(
                    width: width, height: height, geometry: Self.checkMarkGeometry, viewBox: Self.checkMarkViewBox,
                    stroke: stroke, strokeWidth: strokeWidth, strokeLinecap: .round, strokeLinejoin: .round,
                    strokeAlignment: hairline == nil ? nil : .center, effects: effects
                ))
            }
            return PenNode(id: id, common: PenNodeCommon(x: .literal(frame.x), y: .literal(frame.y)), kind: kind)
        }
    }

    /// An edge drawn inside a shape's outline.
    struct Hairline: Friendly {
        /// Its color.
        public var color: PenHexColor
        /// Its width, in points.
        public var width: Double

        /// Creates a hairline.
        ///
        /// - Parameters:
        ///   - color: Its color.
        ///   - width: Its width, in points.
        public init(color: PenHexColor, width: Double) {
            self.color = color
            self.width = width
        }
    }

    /// An outer shadow, as a `.pen` shadow effect spells one: its blur is twice the
    /// Gaussian's sigma, as CSS's is.
    struct Shadow: Friendly {
        /// The horizontal offset, in points.
        public var offsetX: Double
        /// The vertical offset, in points; positive is down.
        public var offsetY: Double
        /// The blur radius, in points.
        public var blur: Double
        /// The shadow's color.
        public var color: PenHexColor

        /// Creates a shadow.
        ///
        /// - Parameters:
        ///   - offsetX: The horizontal offset.
        ///   - offsetY: The vertical offset.
        ///   - blur: The blur radius.
        ///   - color: The color.
        public init(offsetX: Double, offsetY: Double, blur: Double, color: PenHexColor) {
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.blur = blur
            self.color = color
        }

        /// The shadow as a `.pen` outer shadow effect.
        public var effect: PenEffect {
            .shadow(PenEffect.PenShadowEffect(
                shadowType: .outer,
                offset: PenEffect.PenOffset(x: .literal(offsetX), y: .literal(offsetY)),
                blur: .literal(blur),
                color: .literal(color.hex)
            ))
        }
    }
}
