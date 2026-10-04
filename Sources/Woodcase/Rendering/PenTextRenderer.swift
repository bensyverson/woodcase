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
    /// Handles horizontal alignment, vertical alignment, and the node's paint.
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
        guard paint != .nothing, let built = buildAttributedString(from: data, color: paint.coreTextColor) else {
            return
        }
        let size = CGSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
        // One typesetting pass: the block's height, which vertical alignment centers, is
        // the line count times the pitch — the height layout measured.
        let lines = PenTextLines(
            built.string, width: size.width, pitch: built.pitch, firstBaseline: built.firstBaseline
        )

        // Vertical alignment: compute Y offset in top-down (visual) space
        let verticalOffset: CGFloat = switch data.textAlignVertical {
        case .middle:
            (size.height - ceil(lines.height)) / 2
        case .bottom:
            size.height - ceil(lines.height)
        default:
            0
        }
        // Core Text draws bottom-up in a box `size.height` tall; our context is y-down.
        let placed = lines.placed(inBoxOfHeight: size.height)
        let textSpace = CGAffineTransform(translationX: 0, y: verticalOffset + size.height).scaledBy(x: 1, y: -1)

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

    // MARK: - Attributed String Construction

    /// Builds a text node's content in its style, with where its lines are placed.
    ///
    /// Returns nil for content that is absent, empty, or an unresolved variable
    /// reference — there is nothing to draw in any of those cases. Otherwise it is
    /// ``PenTextStyle/attributedString(_:for:)`` for drawing, the one builder layout
    /// measurement also sizes text through.
    ///
    /// Shared with ``PenLayoutEngine/textInkBounds(of:box:)``, which lays out the same
    /// string to measure its glyphs' ink rather than to draw them — one attributed
    /// string, so a divergence in font resolution or paragraph style can never separate
    /// what is drawn from what is measured.
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - color: The glyphs' color (``PenGlyphPaint/coreTextColor``).
    /// - Returns: The styled text, or `nil` when there is nothing to draw.
    static func buildAttributedString(
        from data: PenNode.TextData,
        color: CGColor
    ) -> PenStyledText? {
        guard let text = data.content?.literalValue, !text.isEmpty else { return nil }
        return PenTextStyle(data).attributedString(text, for: .drawing(color: color))
    }
}
