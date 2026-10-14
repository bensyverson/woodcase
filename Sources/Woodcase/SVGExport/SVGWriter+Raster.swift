//
//  SVGWriter+Raster.swift
//  Woodcase
//

import CoreGraphics
import Foundation

extension SVGWriter {
    /// A node SVG has no vocabulary for — a note, prompt or context, a browser placeholder —
    /// as the CG renderer's picture of it, embedded at ``SVGExporter/rasterScale`` over
    /// everything it paints, in its parent's coordinates.
    func rasterNode(_ node: PenNode) -> SVGElement? {
        guard let rect = layoutRects[node.id] else { return nil }
        let extent = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: layoutRects)
        return raster(extent.cgRect) { context in
            PenRenderer.renderNodesIteratively(
                [node], layoutRects: layoutRects, in: context, overrides: [:], imageProvider: imageProvider, postIt: postIt
            )
        }
    }

    /// A connection, as the CG renderer's picture of it over the whole export.
    ///
    /// A connection has no box of its own: it is drawn between its endpoints' canvas rects,
    /// so it is pictured over everything the export frames. Pen keeps connections at the
    /// top level, where the parent's coordinates are the canvas.
    func rasterConnection(_ node: PenNode) -> SVGElement? {
        let canvasRects = PenConnectionRenderer.canvasRects(for: document, layoutRects: layoutRects)
        return raster(bounds.cgRect) { context in
            PenRenderer.renderNodesIteratively(
                [node], layoutRects: layoutRects, canvasRects: canvasRects,
                in: context, overrides: [:], imageProvider: imageProvider, postIt: postIt
            )
        }
    }

    /// One paint SVG cannot draw — an angular or mesh gradient — as the CG renderer's
    /// picture of it through `shape`, laid out over `domain`.
    func rasterPaint(_ fill: PenFill, through shape: SVGShape, domain: CGRect, blend: PenBlendMode?) -> SVGElement? {
        let area = shape.outline.boundingBoxOfPath.insetBy(dx: -1, dy: -1)
        var element = raster(area) { context in
            PenFillRenderer.renderFills(
                .single(fill), clip: shape.outline, fillRule: shape.rule, domain: domain,
                in: context, imageProvider: imageProvider
            )
        }
        element?["style"] = blend?.svgStyle
        return element
    }

    /// An `<image>` covering `area` with what `draw` paints there, drawn in a y-down
    /// context whose coordinates are `area`'s own, at ``SVGExporter/rasterScale``.
    ///
    /// - Returns: The image, or `nil` when the area is empty or the bitmap cannot be made.
    private func raster(_ area: CGRect, draw: (CGContext) -> Void) -> SVGElement? {
        guard !area.isNull, !area.isInfinite else { return nil }
        let scale = CGFloat(SVGExporter.rasterScale)
        let region = CGRect(
            x: area.minX.rounded(.down), y: area.minY.rounded(.down),
            width: area.maxX.rounded(.up) - area.minX.rounded(.down),
            height: area.maxY.rounded(.up) - area.minY.rounded(.down)
        )
        let width = Int(region.width * scale), height = Int(region.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: region.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -region.minX, y: -region.minY)
        draw(context)
        guard let image = context.makeImage(), let href = dataURI(image) else { return nil }
        return SVGElement("image", [
            "x": Double(region.minX).svgNumber, "y": Double(region.minY).svgNumber,
            "width": Double(region.width).svgNumber, "height": Double(region.height).svgNumber,
            "preserveAspectRatio": "none", "href": href,
        ])
    }
}
