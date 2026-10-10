import CoreGraphics
import CoreText
import Foundation

/// Renders text content into a CoreGraphics context using Core Text.
///
/// A text node's fills are its paint. A lone solid color is handed to Core Text, which
/// draws the glyphs in it; any other paint is drawn through the glyphs' outlines over the
/// node's box (see ``PenGlyphPaint`` and ``PenGlyphOutlines``). Both routes share one
/// layout. A node with no enabled paint draws nothing, as Pen draws it.
///
/// Public only for its strikethrough — ``strikethroughKey``, ``drawStrikethrough(lines:in:)``
/// and the bar's metrics — which Core Text does not draw and another renderer must draw
/// the same way. Setting text is ``PenTextStyle``'s job.
public enum PenTextRenderer {
    /// Renders a text node's content into the given context at the specified rect.
    ///
    /// The lines and where they sit in the box are ``PenTextLayout``'s; this draws them
    /// in the node's paint. Empty content draws nothing.
    ///
    /// - Parameters:
    ///   - data: The text node's data containing content and style.
    ///   - rect: The bounding rect (zero-origin) to draw text within: the paint's domain.
    ///   - fills: The fills to paint the glyphs with — the node's own, or an override's.
    ///   - context: The CoreGraphics context (already flipped to top-left origin).
    ///   - imageProvider: Resolves an image fill's URL to an image.
    static func renderText(
        data: PenNode.TextData,
        rect: PenRect,
        fills: PenFills?,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider = { _ in nil }
    ) {
        let paint = PenGlyphPaint(fills: fills)
        let size = CGSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
        guard paint != .nothing,
              let layout = PenTextLayout(data, box: size, color: paint.coreTextColor),
              !layout.lines.lines.isEmpty
        else { return }
        let placed = layout.placed
        let textSpace = layout.textSpace

        switch paint {
        case .nothing:
            return

        case .solid:
            context.saveGState()
            context.concatenate(textSpace)
            for (line, origin) in placed {
                context.textPosition = origin
                CTLineDraw(line, context)
            }
            // Draw strikethrough manually (Core Text has no native support)
            drawStrikethrough(lines: placed, in: context)
            context.restoreGState()

        case .glyphOutlines:
            Self.paint(
                fills, through: PenGlyphOutlines(lines: placed, textSpace: textSpace),
                size: size, in: context, imageProvider: imageProvider
            )
        }
    }
}
