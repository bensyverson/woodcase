//
//  SVGWriter+Text.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

extension SVGWriter {
    /// A text node as real, editable `<text>`: Core Text's own line breaks, one `<tspan>`
    /// per styled run of each line, each pinned to where Core Text set it.
    ///
    /// The lines are ``PenTextLayout``'s — the ones the CG renderer draws — so a wrapped
    /// paragraph breaks where it does on the canvas whatever the SVG reader's own line
    /// breaking would do. Each run starts at its laid-out `x` on its line's baseline and
    /// names its family, size, weight and style; the reader sets the glyphs within a run
    /// with its own copy of the font. Where the reader lacks the font it substitutes one,
    /// and only that run's width drifts — the next run, and the next line, start where
    /// they should. Paint, shadows and run fills follow ``PenTextRenderer``.
    func text(
        _ node: PenNode,
        box: PenRect,
        effects: Effects
    ) -> [SVGElement] {
        guard case let .text(data) = node.kind else { return [] }
        let fills = data.fills
        let paint = PenGlyphPaint(fills: fills)
        let hasOwnFills = node.appliedRuns.contains { $0.fill != nil }
        guard paint != .nothing || hasOwnFills,
              let layout = PenTextLayout(node, box: CGSize(width: box.width, height: box.height)),
              !layout.lines.lines.isEmpty
        else { return [] }

        let shape = textShape(layout)
        let region = (layout.inkBounds ?? .null).union(box.cgRect)
        let ink = shape.element(fill: "#000000")

        var elements = outerShadows(effects.outerShadows, silhouette: ink, region: region)
        switch paint {
        case .nothing:
            elements.append(shape.element(fill: "none"))
        case let .solid(color):
            elements.append(shape.paintedSolid(color, blend: nil))
        case .glyphOutlines:
            elements += self.paint(fills, through: shape, domain: box.cgRect)
        }
        elements += innerShadows(effects.innerShadows, silhouette: ink, region: region)
        return elements
    }

    /// A text node's glyphs as a region to paint, or `nil` when it sets no lines.
    func textShape(_ node: PenNode, box: PenRect) -> SVGShape? {
        guard let layout = PenTextLayout(node, box: CGSize(width: box.width, height: box.height)),
              !layout.lines.lines.isEmpty
        else { return nil }
        return textShape(layout)
    }

    /// A layout's glyphs as a region: its `<text>`, and its glyph outlines for what cannot
    /// be painted through `<text>`.
    private func textShape(_ layout: PenTextLayout) -> SVGShape {
        SVGShape(text: textElement(layout), outline: PenGlyphOutlines(lines: layout.placed, textSpace: layout.textSpace).path)
    }

    /// The `<text>` for a layout, with no paint of its own: a run with its own fill carries
    /// it on its `<tspan>`.
    private func textElement(_ layout: PenTextLayout) -> SVGElement {
        let segments = layout.style.segments(of: layout.text, runs: layout.runs)
        let utf16 = Array(layout.text.utf16)
        var spans: [SVGElement] = []
        for (line, origin) in layout.placed {
            let baseline = origin.applying(layout.textSpace)
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let range = CTRunGetStringRange(run)
                let lower = max(0, range.location), upper = min(utf16.count, range.location + range.length)
                guard lower < upper else { continue }
                let content = String(decoding: utf16[lower ..< upper], as: UTF16.self)
                    .trimmingCharacters(in: .newlines)
                guard !content.isEmpty, CTRunGetGlyphCount(run) > 0 else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let segment = segments.first { $0.range.contains(lower) }
                var span = SVGElement("tspan", [
                    "x": Double(origin.x + position.x).svgNumber,
                    "y": Double(baseline.y).svgNumber,
                ])
                span.setFont(segment?.style ?? layout.style)
                if let fill = segment?.fill {
                    span["fill"] = fill.svgColor
                    span["fill-opacity"] = fill.alpha == 255 ? nil : fill.svgAlpha
                }
                span.text = content
                spans.append(span)
            }
        }
        return SVGElement("text", ["xml:space": "preserve"], children: spans)
    }
}

private extension SVGElement {
    /// Sets a `tspan`'s font from a text style: family, size, weight, style, spacing and
    /// decorations.
    ///
    /// Optical sizing is turned off, so a variable font with an `opsz` axis is set at its
    /// default optical size, as Core Text and Pen set it. Left on, WebKit picks the cut
    /// from the size it lays SVG text out at internally, not the font size, and set 14 pt
    /// Inter in its narrow display cut: `render-text` measured 5.08 against the CG render
    /// before, with every run visibly narrower.
    mutating func setFont(_ style: PenTextStyle) {
        self["style"] = "font-optical-sizing:none"
        self["font-family"] = style.fontFamily
        self["font-size"] = style.fontSize.svgNumber
        self["font-weight"] = style.fontWeight.svgNumber
        self["font-style"] = style.isItalic ? "italic" : nil
        if let spacing = style.letterSpacing, spacing != 0 {
            self["letter-spacing"] = spacing.svgNumber
        }
        let decorations = [style.underline ? "underline" : nil, style.strikethrough ? "line-through" : nil].compactMap(\.self)
        self["text-decoration"] = decorations.isEmpty ? nil : decorations.joined(separator: " ")
    }
}
