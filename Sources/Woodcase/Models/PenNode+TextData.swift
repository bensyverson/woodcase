//
//  PenNode+TextData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Text

    struct TextData: Friendly, PenStrokable {
        public init(
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            content: PenValue<String>? = nil,
            textGrowth: PenTextGrowth? = nil,
            fontFamily: PenValue<String>? = nil,
            fontSize: PenValue<Double>? = nil,
            fontWeight: PenValue<String>? = nil,
            fontStyle: PenValue<String>? = nil,
            letterSpacing: PenValue<Double>? = nil,
            lineHeight: PenValue<Double>? = nil,
            textAlign: PenTextAlign? = nil,
            textAlignVertical: PenTextAlignVertical? = nil,
            underline: PenValue<Bool>? = nil,
            strikethrough: PenValue<Bool>? = nil,
            href: String? = nil,
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
            self.content = content
            self.textGrowth = textGrowth
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.fontStyle = fontStyle
            self.letterSpacing = letterSpacing
            self.lineHeight = lineHeight
            self.textAlign = textAlign
            self.textAlignVertical = textAlignVertical
            self.underline = underline
            self.strikethrough = strikethrough
            self.href = href
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
        public var content: PenValue<String>?
        public var textGrowth: PenTextGrowth?
        public var fontFamily: PenValue<String>?
        public var fontSize: PenValue<Double>?
        public var fontWeight: PenValue<String>?
        public var fontStyle: PenValue<String>?
        public var letterSpacing: PenValue<Double>?
        public var lineHeight: PenValue<Double>?
        public var textAlign: PenTextAlign?
        public var textAlignVertical: PenTextAlignVertical?
        public var underline: PenValue<Bool>?
        public var strikethrough: PenValue<Bool>?
        public var href: String?
        public var fills: PenFills?
        public var stroke: PenFills?
        public var strokeWidth: PenStrokeWidth?
        public var strokeLinecap: PenStrokeCap?
        public var strokeLinejoin: PenStrokeJoin?
        public var strokeAlignment: PenStrokeAlign?
        public var effects: PenEffects?
        public var blendMode: PenBlendMode?

        public enum CodingKeys: String, CodingKey {
            case width, height, content, textGrowth
            case fontFamily, fontSize, fontWeight, fontStyle
            case letterSpacing, lineHeight, textAlign, textAlignVertical
            case underline, strikethrough, href
            case fills = "fill"
            case stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeAlignment
            case effects = "effect", blendMode
        }
    }
}
