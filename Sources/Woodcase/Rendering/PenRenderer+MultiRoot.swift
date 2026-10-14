//
//  PenRenderer+MultiRoot.swift
//  Woodcase
//

import CoreGraphics

public extension PenRenderer {
    /// Renders a selection that may span parents into a new `CGImage`: each root exactly
    /// where the canvas draws it, and nothing else.
    ///
    /// Every root is drawn through its ancestors' placements — their positions, turns and
    /// flips — and cut by every ancestor frame that clips, so a node half hidden by a
    /// clipping card comes out half hidden. The ancestors paint nothing of their own: no
    /// fill, stroke or effect, and neither their opacity nor their blend mode reaches the
    /// root (``PenCanvasRoot``). Roots draw in the canvas's paint order, whatever order they
    /// are named in, and a root inside another root is drawn once, by its ancestor. The
    /// image is transparent wherever no root paints.
    ///
    /// This is the clipboard's PNG; ``SVGExporter/data(_:layoutRects:rootNodeIDs:bounds:imageProvider:postIt:)``
    /// draws the same selection as an SVG, and
    /// `PenLayoutEngine.canvasPaintedExtent(of:in:layoutRects:)`, given every root's id, gives
    /// the bounds that hold everything it paints.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - rootNodeIDs: The roots, in the expanded document's spelling; ids the document
    ///     lacks are skipped.
    ///   - bounds: The canvas region the image covers, in points.
    ///   - scale: Pixels per point. Defaults to 1; a clipboard PNG is usually 2.
    ///   - colorSpace: The image's color space. Defaults to sRGB.
    ///   - imageProvider: Loads the images image fills name.
    ///   - postIt: The words and identity colors notes, prompts and contexts are drawn with.
    /// - Returns: The image, `bounds` × `scale` pixels rounded up to whole pixels, or `nil`
    ///   when that is empty or the bitmap cannot be made.
    static func render(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        rootNodeIDs: [String],
        bounds: PenRect,
        scale: CGFloat = 1,
        colorSpace: CGColorSpace? = nil,
        imageProvider: ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) -> CGImage? {
        let pixelWidth = Int((CGFloat(bounds.width) * scale).rounded(.up))
        let pixelHeight = Int((CGFloat(bounds.height) * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelWidth * 4,
                  space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        // CoreGraphics counts up from the bottom-left; .pen counts down from the top-left.
        context.translateBy(x: 0, y: CGFloat(bounds.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-bounds.x), y: CGFloat(-bounds.y))

        render(
            document, layoutRects: layoutRects, rootNodeIDs: rootNodeIDs, into: context,
            imageProvider: imageProvider, postIt: postIt
        )
        return context.makeImage()
    }

    /// Draws a selection that may span parents into a context already in canvas
    /// coordinates — y down, one unit per point — each root where the canvas draws it.
    ///
    /// The drawing half of ``render(_:layoutRects:rootNodeIDs:bounds:scale:colorSpace:imageProvider:postIt:)``,
    /// for a caller that owns its context: a PDF page, a tile of a larger bitmap.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - rootNodeIDs: The roots; ids the document lacks are skipped.
    ///   - context: The context, in canvas coordinates.
    ///   - imageProvider: Loads the images image fills name.
    ///   - postIt: The words and identity colors notes, prompts and contexts are drawn with.
    static func render(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        rootNodeIDs: [String],
        into context: CGContext,
        imageProvider: ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) {
        let roots = PenCanvasRoot.resolve(rootNodeIDs, in: document, layoutRects: layoutRects)
        guard !roots.isEmpty else { return }
        let connections = roots.contains { if case .connection = $0.node.kind { true } else { false } }
        let canvasRects = connections ? PenConnectionRenderer.canvasRects(for: document, layoutRects: layoutRects) : [:]
        for root in roots {
            context.saveGState()
            for clip in root.clips {
                guard let outline = PenShapeBuilder.buildPath(for: clip.node, rect: clip.placement.box) else { continue }
                var toCanvas = clip.placement.transform.cgAffineTransform
                guard let onCanvas = outline.copy(using: &toCanvas) else { continue }
                context.addPath(onCanvas)
                context.clip()
            }
            context.concatenate(root.parentTransform.cgAffineTransform)
            renderNodesIteratively(
                [root.node], layoutRects: layoutRects, canvasRects: canvasRects,
                in: context, overrides: [:], imageProvider: imageProvider, postIt: postIt
            )
            context.restoreGState()
        }
    }
}
