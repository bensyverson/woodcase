//
//  PenIconFontRenderer.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

/// Renders icon font glyphs into a CoreGraphics context using Core Text.
///
/// Each icon is rendered as a single Unicode glyph from the appropriate icon font, placed
/// in the node's box by the font's metrics, as Pen places it. Which glyph, which face and
/// where are ``PenIconGlyph``'s answer, which other renderers share.
enum PenIconFontRenderer {
    /// Default weight for Material Symbols when none is specified in the node data.
    private static let materialSymbolsDefaultWeight: Double = 200

    /// Renders an icon font glyph into the given context at the specified rect.
    ///
    /// - Parameters:
    ///   - data: The icon node's data containing library, icon and weight.
    ///   - rect: The bounding rect (zero-origin) to draw the icon within: the paint's domain.
    ///   - fills: The fills to paint the glyph with — the node's own, or an override's. A lone
    ///     solid is drawn by Core Text; any other paint through the glyph's outline, as
    ///     ``PenTextRenderer`` paints text; no enabled paint draws nothing (``PenGlyphPaint``).
    ///   - context: The CoreGraphics context (already flipped to top-left origin).
    ///   - imageProvider: Resolves an image fill's URL to an image.
    static func render(
        data: PenNode.IconData,
        rect: PenRect,
        fills: PenFills?,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider = { _ in nil }
    ) {
        let paint = PenGlyphPaint(fills: fills)
        let box = CGSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
        guard paint != .nothing, let glyph = PenIconGlyph(data: data, box: box) else { return }

        let drawAttrs: [CFString: Any] = [
            kCTFontAttributeName: glyph.font,
            kCTForegroundColorAttributeName: paint.coreTextColor,
        ]
        let drawLine = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(kCFAllocatorDefault, glyph.string as CFString, drawAttrs as CFDictionary)!
        )
        // The origin is y down from the box's top; Core Text draws y up from its bottom.
        let origin = CGPoint(x: glyph.origin.x, y: box.height - glyph.origin.y)

        switch paint {
        case .nothing:
            return
        case .solid:
            context.saveGState()
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = origin
            CTLineDraw(drawLine, context)
            context.restoreGState()
        case .glyphOutlines:
            let textSpace = CGAffineTransform(translationX: 0, y: box.height).scaledBy(x: 1, y: -1)
            PenTextRenderer.paint(
                fills, through: PenGlyphOutlines(lines: [(drawLine, origin)], textSpace: textSpace),
                size: box, in: context, imageProvider: imageProvider
            )
        }
    }

    // MARK: - Placement

    /// The text size at which Pen reads an icon font's ascent and descent, each rounded to
    /// a whole point, before scaling them to the icon's size.
    ///
    /// Fitted, not read from Pen's source: Feather's baseline sits at 13/14 of its em in
    /// every probed box (16–128 pt), which is its ascent and descent rounded at 14 pt (13
    /// and 1). 28 and 42 fit the six bundled fonts equally well; 14 is Pen's default text
    /// size. See "Where the glyph sits" in PenIconFonts.md.
    static let metricsReferenceSize: CGFloat = 14

    /// Where Pen puts an icon's glyph in a box of `box`: its pen position from the box's
    /// left edge and its baseline down from the box's top, in points.
    ///
    /// Pen places the glyph by the font's metrics, never by its ink: the advance is centred
    /// across the box, and the line box — ascent plus descent, each rounded to a whole point
    /// at ``metricsReferenceSize`` and scaled to the font's size — is centred down it.
    /// `render-icon-placement.pen` pins this against Pen for every bundled library at two
    /// sizes and in wide and tall boxes.
    ///
    /// - Parameters:
    ///   - font: The icon's font, at the icon's size.
    ///   - codepoint: The glyph's code point, whose advance is centred.
    ///   - box: The icon's box.
    /// - Returns: The glyph's origin, y down.
    static func glyphOrigin(font: CTFont, codepoint: UInt32, box: CGSize) -> CGPoint {
        let size = CTFontGetSize(font)
        var advance = CGSize(width: size, height: 0)
        if let scalar = Unicode.Scalar(codepoint) {
            let characters = Array(String(Character(scalar)).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            if CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) {
                CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advance, 1)
            }
        }
        let reference = metricsReferenceSize
        let ascent = (CTFontGetAscent(font) * reference / size).rounded()
        let descent = (CTFontGetDescent(font) * reference / size).rounded()
        return CGPoint(
            x: (box.width - advance.width) / 2,
            y: box.height / 2 + size * (ascent - descent) / (2 * reference)
        )
    }

    // MARK: - Font Creation

    /// The font an icon is drawn with, at `size` points.
    ///
    /// - Parameters:
    ///   - icon: The resolved icon, which names the face.
    ///   - size: The point size: the shorter side of the icon's box.
    ///   - weight: The node's `weight`, the `wght` axis value for a Material Symbols face.
    ///   - family: The `.pen` library name, which decides whether the weight axis applies.
    /// - Returns: The font to draw and place the glyph with.
    static func font(
        for icon: PenIconFontRegistry.ResolvedIcon, size: CGFloat, weight: Double?, family: String
    ) -> CTFont {
        createFont(name: icon.ctFontName, size: size, weight: weight, family: family)
    }

    /// Creates a CTFont, applying variable weight for Material Symbols (default 200).
    ///
    /// A Material Symbols face also has automatic optical sizing turned off: Core Text
    /// would move its `opsz` axis (20–48) to the point size, where Pen draws every icon
    /// at the font's default optical size, 24. Left on, `vpn_lock` at 48 pt came out in
    /// the lighter display cut, 3.3–4.9 MAE off Pen's in the glyph's window (see
    /// "Which cut of the glyph" in <doc:PenIconFonts>).
    ///
    /// Gated by ``FontRegistryGate``: `CTFontCreateWithName` resolves through Core
    /// Text's font registry, which is a blocking synchronous XPC round trip, and
    /// several of those at once exhaust the cooperative thread pool.
    ///
    /// - Parameters:
    ///   - name: The PostScript name of the face.
    ///   - size: The point size.
    ///   - weight: The `wght` axis value for a Material Symbols face, or `nil` for its
    ///     default.
    ///   - family: The family name, which decides whether the weight axis applies.
    /// - Returns: The font to draw the glyph with.
    private static func createFont(name: String, size: CGFloat, weight: Double?, family: String) -> CTFont {
        FontRegistryGate.withAccess {
            guard family.hasPrefix("Material Symbols") else {
                return CTFontCreateWithName(name as CFString, size, nil)
            }
            let effectiveWeight = weight ?? materialSymbolsDefaultWeight
            // Pen sets only `wght`; the other axes stay at the font's defaults (opsz 24).
            let variation: [CFString: Any] = [
                kCTFontVariationAttribute: [variationAxisTag("wght"): effectiveWeight],
                kCTFontOpticalSizeAttribute: PenTextMeasurer.opticalSizingOff,
            ]
            let descriptor = CTFontDescriptorCreateWithAttributes(variation as CFDictionary)
            let baseFont = CTFontCreateWithName(name as CFString, size, nil)
            return CTFontCreateCopyWithAttributes(baseFont, size, nil, descriptor)
        }
    }

    /// Converts a 4-character OpenType tag string to its UInt32 representation.
    private static func variationAxisTag(_ tag: String) -> UInt32 {
        let bytes = Array(tag.utf8)
        guard bytes.count == 4 else { return 0 }
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}
