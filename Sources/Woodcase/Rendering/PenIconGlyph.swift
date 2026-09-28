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
/// Draw it by setting ``string`` in ``font`` as one Core Text line with its pen at
/// ``origin``, measured y down from the box's top-left, or paint through its outline.
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
        font = PenIconFontRenderer.font(
            for: resolved, size: min(box.width, box.height), weight: weight, family: library
        )
        origin = PenIconFontRenderer.glyphOrigin(font: font, codepoint: resolved.codepoint, box: box)
    }
}
