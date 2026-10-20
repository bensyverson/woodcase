import CoreGraphics
import CoreText
import Foundation

/// An icon's glyph: the character it draws, the face and size it draws it in, and where
/// Pen puts it in the icon's box.
///
/// This is what Woodcase's CG renderer draws an icon from, public so that another renderer
/// draws the same glyph at the same place rather than a copy of the rules (RapidPro's text
/// rasterizer does). It settles, in one place:
///
/// - **Which glyph.** The library's own glyph for the name (``PenIconFontRegistry``), or
///   the library's "unknown icon" glyph for a name it does not know — the substitution
///   Pen's own engine makes (verified with `pen interactive`, leaf AuqQs) — never nothing.
/// - **Which face.** The library's font at the box's shorter side; a Material Symbols face
///   at the node's `weight` on its `wght` axis, 200 when the node sets none, and at the
///   font's default optical size whatever the icon's size, as Pen draws it.
/// - **Where.** Pen's placement by the font's metrics, never the glyph's ink: see "Where
///   the glyph sits" in <doc:PenIconFonts>.
///
/// It also sets the glyph as Core Text draws it, so no renderer builds an attributed string
/// of its own: draw ``line(color:)`` with the context's text position at ``lineOrigin``
/// under ``textSpace``, or paint through ``outlines(color:)``; ``inkBounds`` is the ink
/// that line paints. Woodcase's CG renderer, ``PenLayoutEngine/iconInkBounds(of:box:)``
/// and RapidPro's rasterizer all draw or measure this one line.
///
/// ```swift
/// guard let glyph = PenIconGlyph(data: iconData, box: box) else { return }
/// context.concatenate(glyph.textSpace)   // onto a y-down context over the box
/// context.textPosition = glyph.lineOrigin
/// CTLineDraw(glyph.line(color: color), context)
/// ```
///
/// Coordinates are the box's own — origin at its top-left, y down — except
/// ``lineOrigin``, which is Core Text's y-up space over the box.
///
/// Hashable, not `Friendly`: `CTFont` is neither `Codable` nor `Sendable`.
public struct PenIconGlyph: Hashable {
    /// The icon's one-character string: its glyph's code point.
    public let string: String
    /// The face the glyph is drawn in, at the icon's size.
    public let font: CTFont
    /// The glyph's pen position from the box's left edge and its baseline down from the
    /// box's top, in points.
    public let origin: CGPoint
    /// The icon's box the glyph is placed in, in points.
    public let box: CGSize

    /// The glyph an icon node draws in a box of `box`.
    ///
    /// - Parameters:
    ///   - data: The icon node's data: its library, icon name and weight, resolved.
    ///   - box: The icon's box, in points.
    /// - Returns: `nil` when the node names no library or no icon, or a library Woodcase
    ///   has no font for — nothing is drawn.
    public init?(data: PenNode.IconData, box: CGSize) {
        guard let library = data.library?.literalValue, let icon = data.icon?.literalValue else { return nil }
        self.init(library: library, icon: icon, weight: data.weight?.literalValue, box: box)
    }

    /// The glyph `icon` from `library` draws in a box of `box`.
    ///
    /// - Parameters:
    ///   - library: The `.pen` library name, such as `lucide` or `Material Symbols Outlined`.
    ///   - icon: The icon's name in that library.
    ///   - weight: The node's `weight`: the `wght` axis value of a Material Symbols face,
    ///     ignored by every other library; `nil` for the default.
    ///   - box: The icon's box, in points.
    /// - Returns: `nil` for a library Woodcase has no font for — nothing is drawn.
    public init?(library: String, icon: String, weight: Double?, box: CGSize) {
        let registry = PenIconFontRegistry.shared
        guard let resolved = registry.resolve(family: library, name: icon) ?? registry.placeholder(family: library),
              let scalar = Unicode.Scalar(resolved.codepoint)
        else {
            return nil
        }
        string = String(Character(scalar))
        self.box = box
        font = PenIconFontRenderer.font(
            for: resolved, size: min(box.width, box.height), weight: weight, family: library
        )
        origin = PenIconFontRenderer.glyphOrigin(font: font, codepoint: resolved.codepoint, box: box)
    }

    /// The glyph set as one Core Text line in ``font``, its runs colored `color`.
    ///
    /// This is the one attributed string an icon is drawn and measured from. Color never
    /// changes geometry, so a line built only to measure can take the default.
    ///
    /// - Parameter color: The glyph's color, which `CTLineDraw` reads from the run; a
    ///   color font's glyphs keep their own.
    /// - Returns: The line, whose pen sits at ``lineOrigin``.
    public func line(color: CGColor = PenTextLayout.defaultColor) -> CTLine {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: false,
            kCTForegroundColorAttributeName: color,
        ]
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, string as CFString, attributes as CFDictionary)!
        // Typesetting reaches fontd by itself, so it goes through the gate.
        return FontRegistryGate.withAccess { CTLineCreateWithAttributedString(attributed) }
    }

    /// The line's pen position in Core Text's y-up space over the box: ``origin`` with its
    /// y measured up from the box's bottom. Set it as the context's text position under
    /// ``textSpace``.
    public var lineOrigin: CGPoint {
        CGPoint(x: origin.x, y: box.height - origin.y)
    }

    /// The map from ``lineOrigin``'s y-up space into the box's y-down space: concatenate it
    /// onto a y-down context over the box before drawing the line.
    public var textSpace: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: box.height).scaledBy(x: 1, y: -1)
    }

    /// The glyph's outline at its place, for painting a non-solid fill through
    /// (``PenGlyphPaint/glyphOutlines``).
    ///
    /// - Parameter color: The line's color: only a color font's glyphs, which have no
    ///   outline and are drawn by Core Text, read it.
    /// - Returns: The outlines in the box's y-down space.
    public func outlines(color: CGColor = PenTextLayout.defaultColor) -> PenGlyphOutlines {
        PenGlyphOutlines(lines: [(line(color: color), lineOrigin)], textSpace: textSpace)
    }

    /// The tight bounds of the glyph's outline at its place, in the box's y-down space, or
    /// `nil` when the glyph draws nothing.
    ///
    /// The ink ``line(color:)`` paints, measured from its outline as Pen measures an icon's
    /// fill path (`PenLayoutEngine.outlineBounds(of:)`), not from Core Text's looser image
    /// bounds; not confined to the box. Computed on each read.
    public var inkBounds: CGRect? {
        guard var bounds = PenLayoutEngine.outlineBounds(of: line()) else { return nil }
        bounds.origin.x += lineOrigin.x
        bounds.origin.y += lineOrigin.y
        return bounds.applying(textSpace)
    }
}
