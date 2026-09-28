//
//  PenNode+EllipseData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Ellipse

    struct EllipseData: Friendly, PenStrokable {
        public init(
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            innerRadius: PenValue<Double>? = nil,
            startAngle: PenValue<Double>? = nil,
            sweepAngle: PenValue<Double>? = nil,
            fills: PenFills? = nil,
            stroke: PenFills? = nil,
            strokeWidth: PenStrokeWidth? = nil,
            strokeLinecap: PenStrokeCap? = nil,
            strokeLinejoin: PenStrokeJoin? = nil,
            strokeAlignment: PenStrokeAlign? = nil,
            effects: PenEffects? = nil,
            blendMode: PenBlendMode? = nil
        ) {
            self.width = width
            self.height = height
            self.innerRadius = innerRadius
            self.startAngle = startAngle
            self.sweepAngle = sweepAngle
            self.fills = fills
            self.stroke = stroke
            self.strokeWidth = strokeWidth
            self.strokeLinecap = strokeLinecap
            self.strokeLinejoin = strokeLinejoin
            self.strokeAlignment = strokeAlignment
            self.effects = effects
            self.blendMode = blendMode
        }

        public var width: PenSizing?
        public var height: PenSizing?
        public var innerRadius: PenValue<Double>?
        public var startAngle: PenValue<Double>?
        public var sweepAngle: PenValue<Double>?
        public var fills: PenFills?
        public var stroke: PenFills?
        public var strokeWidth: PenStrokeWidth?
        public var strokeLinecap: PenStrokeCap?
        public var strokeLinejoin: PenStrokeJoin?
        public var strokeAlignment: PenStrokeAlign?
        public var effects: PenEffects?
        public var blendMode: PenBlendMode?

        public enum CodingKeys: String, CodingKey {
            case width, height, innerRadius, startAngle, sweepAngle
            case fills = "fill"
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
            case effects = "effect", blendMode
        }
    }
}
