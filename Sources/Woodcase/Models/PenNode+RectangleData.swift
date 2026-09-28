//
//  PenNode+RectangleData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Rectangle

    struct RectangleData: Friendly, PenStrokable {
        public init(
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            cornerRadius: PenCornerRadius? = nil,
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
            self.cornerRadius = cornerRadius
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
        public var cornerRadius: PenCornerRadius?
        public var fills: PenFills?
        public var stroke: PenFills?
        public var strokeWidth: PenStrokeWidth?
        public var strokeLinecap: PenStrokeCap?
        public var strokeLinejoin: PenStrokeJoin?
        public var strokeAlignment: PenStrokeAlign?
        public var effects: PenEffects?
        public var blendMode: PenBlendMode?

        public enum CodingKeys: String, CodingKey {
            case width, height, cornerRadius
            case fills = "fill"
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
            case effects = "effect", blendMode
        }
    }
}
