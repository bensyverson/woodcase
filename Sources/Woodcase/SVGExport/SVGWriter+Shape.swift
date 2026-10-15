//
//  SVGWriter+Shape.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A node's own content — everything but its children — in Pen's paint order, as
    /// `PenRenderer.renderOwnContent` draws it: outer shadows, fills, inner shadows, stroke.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - box: Its draw rect, in its own coordinates.
    ///   - effects: Its enabled effects.
    /// - Returns: The elements, bottom to top.
    func ownContent(
        _ node: PenNode,
        box: PenRect,
        effects: Effects
    ) -> [SVGElement] {
        switch node.kind {
        case let .frame(data):
            shape(node, fills: data.fills, stroke: data, box: box, effects: effects)
        case let .rectangle(data):
            shape(node, fills: data.fills, stroke: data, box: box, effects: effects)
        case let .ellipse(data):
            shape(node, fills: data.fills, stroke: data, box: box, effects: effects)
        case let .polygon(data):
            shape(node, fills: data.fills, stroke: data, box: box, effects: effects)
        case let .path(data):
            shape(node, fills: data.fills, stroke: data, box: box, effects: effects)
        case let .line(data):
            line(node, data: data, box: box)
        case .text:
            text(node, box: box, effects: effects)
        case let .icon(data):
            icon(node, data: data, box: box, effects: effects)
        case .group:
            // A group paints nothing but its children; they cast its shadows.
            outerShadows(
                effects.outerShadows, silhouette: groupSilhouette(of: node.kind.inlineChildren),
                region: groupRegion(node, box: box)
            )
        default:
            []
        }
    }

    /// A closed shape: its silhouette's outer shadows, its fills, its inner shadows, its stroke.
    private func shape(
        _ node: PenNode,
        fills: PenFills?,
        stroke: any PenStrokable,
        box: PenRect,
        effects: Effects
    ) -> [SVGElement] {
        guard let outline = PenShapeBuilder.buildPath(for: node, rect: box) else { return [] }
        let rule = PenShapeBuilder.fillRule(for: node)
        var elements: [SVGElement] = []
        if !effects.outerShadows.isEmpty, let silhouette = PenShadowSilhouette.path(for: node, rect: box) {
            let ink = SVGShape(path: silhouette.path, rule: silhouette.rule).element(fill: "#000000")
            elements += outerShadows(effects.outerShadows, silhouette: ink, region: silhouette.path.boundingBoxOfPath)
        }
        let shape = SVGShape(path: outline, rule: rule)
        elements += paint(fills, through: shape, domain: box.cgRect)
        elements += innerShadows(effects.innerShadows, silhouette: shape.element(fill: "#000000"), region: outline.boundingBoxOfPath)
        elements += self.stroke(
            stroke.drawn(on: node), path: outline, box: box,
            roundedBox: PenStrokeRenderer.roundedBox(for: node, rect: box), dash: node.strokeDash,
            miterLimit: node.strokeMiterLimit
        )
        return elements
    }

    /// A line: only its stroke, laid over its band where it has no extent.
    private func line(_ node: PenNode, data: PenNode.LineData, box: PenRect) -> [SVGElement] {
        guard let path = PenShapeBuilder.buildPath(for: node, rect: box) else { return [] }
        let stroke = data.drawn(on: node)
        return self.stroke(
            stroke, path: path, box: PenRenderer.lineBand(box, strokeWidth: stroke.uniformStrokeWidth ?? 1),
            roundedBox: nil, dash: node.strokeDash, miterLimit: node.strokeMiterLimit
        )
    }

    /// An icon: its glyph's outline, painted and shadowed like a shape, so it draws without
    /// the icon font installed wherever the SVG is opened.
    private func icon(
        _: PenNode,
        data: PenNode.IconData,
        box: PenRect,
        effects: Effects
    ) -> [SVGElement] {
        let size = CGSize(width: box.width, height: box.height)
        guard PenGlyphPaint(fills: data.fills) != .nothing,
              let glyph = PenIconGlyph(data: data, box: size)
        else { return [] }
        let outline = glyph.outlines().path
        guard !outline.isEmpty else { return [] }
        let shape = SVGShape(path: outline, rule: .winding)
        let ink = shape.element(fill: "#000000")
        return outerShadows(effects.outerShadows, silhouette: ink, region: outline.boundingBoxOfPath)
            + paint(data.fills, through: shape, domain: box.cgRect)
            + innerShadows(effects.innerShadows, silhouette: ink, region: outline.boundingBoxOfPath)
    }

    /// What a group may paint, in its own coordinates: the region its shadows' filters
    /// must cover.
    func groupRegion(_ node: PenNode, box: PenRect) -> CGRect {
        (PenLayoutEngine.localPaintedExtent(of: node, box: box, layoutRects: layoutRects) ?? box).cgRect
    }
}
