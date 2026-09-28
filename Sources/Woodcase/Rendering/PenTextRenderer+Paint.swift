import CoreGraphics
import CoreText
import Foundation

extension PenTextRenderer {
    /// Draws fills through glyph outlines, laid out over the node's box.
    ///
    /// Glyphs from a colour font (emoji) have no outline to clip to; they are drawn as Core
    /// Text draws them, in their own colours, before the paint goes over the rest.
    ///
    /// - Parameters:
    ///   - fills: The fills to draw.
    ///   - outlines: The glyphs, in the node's y-down space.
    ///   - size: The node's size; the paint's domain is the box of that size at the origin.
    ///   - context: The context, y-down with the node's origin at (0, 0).
    ///   - imageProvider: Resolves an image fill's URL.
    static func paint(
        _ fills: PenFills?,
        through outlines: PenGlyphOutlines,
        size: CGSize,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        outlines.drawColorGlyphs(in: context)
        guard !outlines.path.isEmpty else { return }
        PenFillRenderer.renderFills(
            fills, clip: outlines.path, fillRule: .winding, domain: CGRect(origin: .zero, size: size),
            in: context, imageProvider: imageProvider
        )
    }
}
