//
//  PenNode+FrameData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Frame

    struct FrameData: Friendly, PenStrokable {
        public init(
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            cornerRadius: PenCornerRadius? = nil,
            clip: PenValue<Bool>? = nil,
            fills: PenFills? = nil,
            stroke: PenFills? = nil,
            strokeWidth: PenStrokeWidth? = nil,
            strokeLinecap: PenStrokeCap? = nil,
            strokeLinejoin: PenStrokeJoin? = nil,
            strokeAlignment: PenStrokeAlign? = nil,
            effects: PenEffects? = nil,
            blendMode: PenBlendMode? = nil,
            layout: PenLayoutDirection? = nil,
            gap: PenValue<Double>? = nil,
            padding: PenPadding? = nil,
            justifyContent: PenJustifyContent? = nil,
            alignItems: PenAlignItems? = nil,
            slot: [String]? = nil,
            children: [PenNode]? = nil
        ) {
            self.width = width
            self.height = height
            self.cornerRadius = cornerRadius
            self.clip = clip
            self.fills = fills
            self.stroke = stroke
            self.strokeWidth = strokeWidth
            self.strokeLinecap = strokeLinecap
            self.strokeLinejoin = strokeLinejoin
            self.strokeAlignment = strokeAlignment
            self.effects = effects
            self.blendMode = blendMode
            self.layout = layout
            self.gap = gap
            self.padding = padding
            self.justifyContent = justifyContent
            self.alignItems = alignItems
            self.slot = slot
            self.children = children
        }

        public var width: PenSizing?
        public var height: PenSizing?
        public var cornerRadius: PenCornerRadius?
        public var clip: PenValue<Bool>?
        public var fills: PenFills?
        public var stroke: PenFills?
        public var strokeWidth: PenStrokeWidth?
        public var strokeLinecap: PenStrokeCap?
        public var strokeLinejoin: PenStrokeJoin?
        public var strokeAlignment: PenStrokeAlign?
        public var effects: PenEffects?
        public var blendMode: PenBlendMode?
        public var layout: PenLayoutDirection?
        public var gap: PenValue<Double>?
        public var padding: PenPadding?
        public var justifyContent: PenJustifyContent?
        public var alignItems: PenAlignItems?
        /// Accepted node types for this slot frame in a component.
        public var slot: [String]?
        public var children: [PenNode]?

        public enum CodingKeys: String, CodingKey {
            case width, height, cornerRadius, clip
            case fills = "fill"
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
            case effects = "effect"
            case blendMode, layout, gap, padding
            case justifyContent, alignItems, slot, children
        }
    }
}
