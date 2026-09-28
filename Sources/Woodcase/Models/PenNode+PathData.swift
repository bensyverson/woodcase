//
//  PenNode+PathData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Path

    struct PathData: Friendly, PenStrokable {
        public init(
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            geometry: String? = nil,
            viewBox: PenViewBox? = nil,
            fillRule: PenFillRule? = nil,
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
            self.geometry = geometry
            self.viewBox = viewBox
            self.fillRule = fillRule
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
        public var geometry: String?
        /// The SVG coordinate space `geometry` is expressed in; `nil` means the tight
        /// bounding box of the geometry is stretched to fill the node box.
        public var viewBox: PenViewBox?
        public var fillRule: PenFillRule?
        public var fills: PenFills?
        public var stroke: PenFills?
        public var strokeWidth: PenStrokeWidth?
        public var strokeLinecap: PenStrokeCap?
        public var strokeLinejoin: PenStrokeJoin?
        public var strokeAlignment: PenStrokeAlign?
        public var effects: PenEffects?
        public var blendMode: PenBlendMode?

        public enum CodingKeys: String, CodingKey {
            case width, height, geometry, viewBox, fillRule
            case fills = "fill"
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
            case effects = "effect", blendMode
        }
    }
}
