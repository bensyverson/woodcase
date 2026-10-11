import CoreGraphics
import CoreText
import Foundation

/// Renders text content into a CoreGraphics context using Core Text.
///
/// A text node's fills are its paint. A lone solid color is handed to Core Text, which
/// draws the glyphs in it; any other paint is drawn through the glyphs' outlines over the
/// node's box (see ``PenGlyphPaint`` and ``PenGlyphOutlines``). Both routes share one
/// layout. A node with no enabled paint draws nothing, as Pen draws it — except its runs
/// with a fill of their own (``PenTextRun/fill``), which draw in that color on every route.
///
/// Public only for what Core Text does not decide and another renderer must draw the same
/// way: its strikethrough — ``strikethroughKey``, ``drawStrikethrough(lines:in:)`` and the
/// bar's metrics — and the mark on a run with its own fill, ``runFillKey``. Setting text is
/// ``PenTextStyle``'s job.
public enum PenTextRenderer {
    /// Renders a text node's content into the given context at the specified rect.
    ///
    /// The lines and where they sit in the box are ``PenTextLayout``'s; this draws them
    /// in the node's paint. Empty content draws nothing.
    ///
    /// - Parameters:
    ///   - node: The text node: its content, style and — in its metadata — its runs.
    ///   - rect: The bounding rect (zero-origin) to draw text within: the paint's domain.
    ///   - fills: The fills to paint the glyphs with — the node's own, or an override's.
    ///   - context: The CoreGraphics context (already flipped to top-left origin).
    ///   - imageProvider: Resolves an image fill's URL to an image.
    static func renderText(
        node: PenNode,
        rect: PenRect,
        fills: PenFills?,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider = { _ in nil }
    ) {
        let paint = PenGlyphPaint(fills: fills)
        let size = CGSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
        // A run with a fill of its own draws even where the node has no paint: the rest of
        // the text is then set in a clear color, which draws nothing.
        let hasOwnFills = node.appliedRuns.contains { $0.fill != nil }
        let color = paint == .nothing ? CGColor(gray: 0, alpha: 0) : paint.coreTextColor
        guard paint != .nothing || hasOwnFills,
              let layout = PenTextLayout(node, box: size, color: color),
              !layout.lines.lines.isEmpty
        else { return }
        let placed = layout.placed
        let textSpace = layout.textSpace

        switch paint {
        case .nothing, .solid:
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
