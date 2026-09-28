//
//  PenBrowserPlaceholder.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

/// Draws a `browser` node as a quiet placeholder: Woodcase never loads the page.
///
/// Pen draws a live snapshot of the page, which no offline renderer can reproduce and
/// which would make a render depend on the network. So the node is drawn as "a web
/// view goes here" — a light neutral fill, a thin neutral border inside the edge, and
/// the stored URL (or `browser` when there is none) as a small grey label, centred and
/// truncated to fit. Everything is clipped to the node's corner radius.
///
/// The node's own paint wins where it has any: a declared stroke replaces the default
/// border, and its effects are drawn by ``PenRenderer`` as on any other shape — the
/// fill is what casts an outer shadow, as the page's snapshot does in Pen. A browser
/// takes no fill in the format, so the placeholder fill is always drawn.
///
/// The look itself is ``Style``, public so that every renderer built on Woodcase draws
/// the same placeholder from the same values.
public enum PenBrowserPlaceholder {
    /// Draws the placeholder for a browser node.
    ///
    /// - Parameters:
    ///   - data: The browser's payload.
    ///   - node: The node, for its shape.
    ///   - rect: The zero-origin rect to draw in.
    ///   - style: The placeholder's look; ``Style/standard`` is what ``PenRenderer`` draws.
    ///   - context: The context, already flipped to a top-left origin.
    static func render(
        _ data: PenNode.BrowserData,
        node: PenNode,
        rect: PenRect,
        style: Style = .standard,
        in context: CGContext
    ) {
        guard let path = PenShapeBuilder.buildPath(for: node, rect: rect),
              let fill = PenColorParser.parse(style.fillHex)
        else { return }

        context.saveGState()
        context.addPath(path)
        context.setFillColor(fill)
        context.fillPath()

        // Only the fill stands for the page's snapshot; the border and the label
        // must not cast a second shadow across it.
        context.setShadow(offset: .zero, blur: 0, color: nil)
        PenStrokeRenderer.renderStroke(
            data.stroke == nil ? defaultBorder(style) : data, path: path, rect: rect,
            roundedBox: PenStrokeRenderer.roundedBox(for: node, rect: rect),
            in: context
        )

        context.addPath(path)
        context.clip()
        drawLabel(style.label(for: data), in: rect, style: style, context: context)
        context.restoreGState()
    }

    // MARK: - Private

    /// The border a browser gets when it declares no stroke of its own.
    private static func defaultBorder(_ style: Style) -> PenNode.BrowserData {
        PenNode.BrowserData(
            stroke: .single(.shorthand(style.borderHex)),
            strokeWidth: .uniform(.literal(style.borderWidth)),
            strokeAlignment: style.borderAlignment
        )
    }

    /// Draws one line of text, centred in `rect` and truncated with an ellipsis to
    /// fit inside the style's label inset.
    private static func drawLabel(_ text: String, in rect: PenRect, style: Style, context: CGContext) {
        let available = rect.width - 2 * style.labelInset
        guard available > 0, let colour = PenColorParser.parse(style.labelHex) else { return }

        let font = PenTextMeasurer.resolveFont(
            family: PenTextMeasurer.defaultFontFamily, size: style.labelSize, weight: "normal", style: "normal"
        )
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: colour,
        ] as CFDictionary
        let full = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        let ellipsis = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "…" as CFString, attributes))
        guard let line = CTLineCreateTruncatedLine(full, available, .end, ellipsis) else { return }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let originX = (CGFloat(rect.width) - CGFloat(width)) / 2
        let baseline = CGFloat(rect.height) / 2 + (ascent - descent) / 2

        // Core Text draws y-up; the context is y-down, so flip about the baseline.
        context.saveGState()
        context.translateBy(x: originX, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
