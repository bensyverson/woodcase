//
//  PenRenderer+PostIt.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

public extension PenRenderer {
    /// Draws a note's, prompt's or context's expansion into a context whose origin is the
    /// node's top-left, y down.
    ///
    /// Each shape part is drawn as its node (``PenPostItExpansion/Shape/node(id:frame:)``)
    /// through the renderer's own node path, so its shadows and hairline are this
    /// renderer's shadows and strokes; each text part is set with ``PenTextLayout``. The
    /// renderer draws every note this way, and an editor can call it to draw one alone.
    ///
    /// - Parameters:
    ///   - expansion: The expansion (``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:)``).
    ///   - context: The context, flipped to a top-left origin and moved to the node.
    static func draw(_ expansion: PenPostItExpansion, in context: CGContext) {
        for (index, part) in expansion.parts.enumerated() {
            switch part.paint {
            case let .shape(shape):
                let node = shape.node(id: "\(index)-\(part.role.rawValue)", frame: part.frame)
                renderNodesIteratively(
                    [node], layoutRects: [node.id: part.frame], in: context, overrides: [:], imageProvider: { _ in nil }
                )
            case let .text(text):
                draw(text, in: part.frame, context: context)
            }
        }
    }
}

extension PenRenderer {
    /// Draws a note, prompt or context in its placement and opacity; a comment, which has no
    /// expansion, draws nothing.
    static func renderPostIt(
        _ ref: NodeRef,
        layoutRects: [String: PenRect],
        overrides: NodeOverrides?,
        in context: CGContext,
        options: PenPostIt.DrawingOptions
    ) {
        // Saves the graphics state; restored below.
        guard let box = enter(ref, layoutRects: layoutRects, overrides: overrides, in: context) else { return }
        defer { context.restoreGState() }
        guard let expansion = PenPostIt.expansion(
            of: ref.node, width: box.width, height: box.height, labels: options.labels, identityColor: options.identityColor
        ) else { return }
        let opacity = overrides?.opacity ?? ref.node.common.opacity?.literalValue
        let isTranslucent = opacity.map { $0 < 1 } ?? false
        if let opacity, isTranslucent {
            context.setAlpha(CGFloat(opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        draw(expansion, in: context)
        if isTranslucent {
            context.endTransparencyLayer()
        }
    }

    /// Sets one text part in its frame and draws it, top-aligned.
    private static func draw(_ text: PenPostItExpansion.Text, in frame: PenRect, context: CGContext) {
        let layout = PenTextLayout(
            text: text.string, style: text.style, runs: text.runs, indents: text.indents,
            box: CGSize(width: frame.width, height: frame.height), color: text.color.sRGBColor
        )
        let placed = layout.placed
        guard !placed.isEmpty else { return }
        context.saveGState()
        context.translateBy(x: CGFloat(frame.x), y: CGFloat(frame.y))
        context.concatenate(layout.textSpace)
        for (line, origin) in placed {
            context.textPosition = origin
            CTLineDraw(line, context)
        }
        PenTextRenderer.drawStrikethrough(lines: placed, in: context)
        context.restoreGState()
    }
}
