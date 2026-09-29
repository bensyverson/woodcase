//
//  PenStrokeRenderer+Style.swift
//  Woodcase
//

import CoreGraphics

extension PenStrokeRenderer {
    /// How a uniform stroke is drawn: width, alignment, join and cap.
    struct Style: Friendly {
        /// The miter limit both the solid and the painted path use — CoreGraphics' default.
        static let miterLimit: CGFloat = 10

        /// The stroke's width in points.
        let width: CGFloat
        /// Where the stroke sits relative to the outline.
        let alignment: PenStrokeAlign
        /// The line join, `nil` meaning miter.
        let penJoin: PenStrokeJoin?
        /// The line cap, `nil` meaning butt.
        let penCap: PenStrokeCap?

        /// The CoreGraphics line join.
        var join: CGLineJoin {
            switch penJoin {
            case .miter, nil: .miter
            case .bevel: .bevel
            case .round: .round
            }
        }

        /// The CoreGraphics line cap.
        var cap: CGLineCap {
            switch penCap {
            case .butt, nil: .butt
            case .round: .round
            case .square: .square
            }
        }

        /// The width the path is stroked at: the stroke's own for a centered stroke, twice
        /// it for inner and outer, whose other half the alignment clip removes.
        var outlineWidth: CGFloat {
            alignment == .center ? width : width * 2
        }

        /// The rectangle an outer solid stroke's complement clip spans: the path's box
        /// grown by twice the width. Kept as it always was so solid strokes do not move.
        func solidOuterBounds(of path: CGPath) -> CGRect {
            path.boundingBox.insetBy(dx: -width * 2, dy: -width * 2)
        }
    }

    /// The color of a stroke that is exactly one solid paint with no blend mode, or `nil`
    /// when the stroke needs the general paint path (a gradient, an image, a stack, a blend).
    static func singleSolidColor(_ fills: PenFills) -> CGColor? {
        let all = fills.all
        guard all.count == 1, let only = all.first else { return nil }
        if case let .shorthand(hex) = only {
            return PenColorParser.parse(hex)
        }
        if case let .color(colorFill) = only,
           colorFill.blendMode == nil,
           colorFill.enabled?.literalValue != false,
           let hex = colorFill.color.literalValue
        {
            return PenColorParser.parse(hex)
        }
        return nil
    }
}
