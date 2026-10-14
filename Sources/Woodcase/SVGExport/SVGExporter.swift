//
//  SVGExporter.swift
//  Woodcase
//

import CoreGraphics
import Foundation

/// Writes nodes as an SVG document: the vector twin of ``PenRenderer``.
///
/// It draws what the CG reference renderer draws, in the same order and from the same
/// geometry — every outline is the renderer's own `CGPath` — but as SVG elements a vector
/// editor can open: shapes as `<path>`, paints as solid colors, `<linearGradient>` and
/// `<radialGradient>`, image fills as embedded PNG, text as real `<text>`, strokes as SVG
/// strokes cut to their alignment, shadows and blurs as SVG filters. What SVG has no words
/// for is embedded as the CG renderer's own picture of it, at ``rasterScale``; see
/// <doc:PenSVGExport> for the full list and what each choice costs.
///
/// Two framings, like the raster renderer's:
///
/// - **On the canvas** — ``data(_:layoutRects:rootNodeIDs:bounds:imageProvider:postIt:)``:
///   any number of roots under any parents, each drawn where the canvas draws it, through
///   its ancestors' placements and clips, cropped to `bounds`. The clipboard's SVG, and the
///   twin of ``PenRenderer/render(_:layoutRects:rootNodeIDs:bounds:scale:colorSpace:imageProvider:postIt:)``.
/// - **In its parent's frame** — ``data(_:layoutRects:rootNodeID:region:imageProvider:postIt:)``:
///   one subtree in the frame its layout rect is in, as `woodcase shot` frames a PNG.
///
/// The document must be expanded (``PenRefExpander``) and resolved
/// (``PenVariableResolver``) first, as for the renderer: an instance draws as its expanded
/// subtree, and an unexpanded `ref` draws nothing.
///
/// ```swift
/// let bounds = PenLayoutEngine.canvasPaintedExtent(of: selection, in: document, layoutRects: rects)!
/// let svg = SVGExporter.data(document, layoutRects: rects, rootNodeIDs: selection, bounds: bounds)
/// ```
public enum SVGExporter {
    /// Pixels per point of every picture the export embeds in place of something SVG cannot
    /// say: an angular or mesh gradient, a note, a browser placeholder, a connection.
    public static let rasterScale: Double = 2

    /// The SVG of a selection that may span parents, each root where the canvas draws it.
    ///
    /// Each root is drawn through its ancestors' placements and cut by every ancestor frame
    /// that clips; the ancestors paint nothing of their own (``PenCanvasRoot``). Roots draw
    /// in the canvas's paint order, and a root inside another root is drawn once.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - rootNodeIDs: The roots, in the expanded document's spelling.
    ///   - bounds: The canvas region the SVG frames, its `viewBox`; `nil` for everything the
    ///     roots paint, `PenLayoutEngine.canvasPaintedExtent(of:in:layoutRects:)` of them all.
    ///   - imageProvider: Loads the images image fills name; their pixels are embedded.
    ///   - postIt: The words and identity colors notes, prompts and contexts are drawn with.
    /// - Returns: The SVG document's UTF-8 bytes, or `nil` when no root is in the document.
    public static func data(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        rootNodeIDs: [String],
        bounds: PenRect? = nil,
        imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) -> Data? {
        string(
            document, layoutRects: layoutRects, rootNodeIDs: rootNodeIDs, bounds: bounds,
            imageProvider: imageProvider, postIt: postIt
        ).map { Data($0.utf8) }
    }

    /// The SVG of a selection, as text: ``data(_:layoutRects:rootNodeIDs:bounds:imageProvider:postIt:)``
    /// before encoding, for a caller that inlines it in HTML or puts it on a pasteboard as
    /// a string.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - rootNodeIDs: The roots, in the expanded document's spelling.
    ///   - bounds: The canvas region the SVG frames; `nil` for everything the roots paint.
    ///   - imageProvider: Loads the images image fills name.
    ///   - postIt: The words and identity colors notes, prompts and contexts are drawn with.
    /// - Returns: The SVG document, or `nil` when no root is in the document.
    public static func string(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        rootNodeIDs: [String],
        bounds: PenRect? = nil,
        imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) -> String? {
        let roots = PenCanvasRoot.resolve(rootNodeIDs, in: document, layoutRects: layoutRects)
        guard !roots.isEmpty else { return nil }
        let frame = bounds
            ?? PenLayoutEngine.canvasPaintedExtent(of: roots.map(\.node.id), in: document, layoutRects: layoutRects)
            ?? PenRect(x: 0, y: 0, width: 0, height: 0)
        let writer = SVGWriter(
            document: document, layoutRects: layoutRects, bounds: frame, imageProvider: imageProvider, postIt: postIt
        )
        return writer.document(roots.compactMap { writer.root($0) })
    }

    /// The SVG of one subtree in its parent's frame — the frame its layout rect is in — as
    /// `woodcase shot` frames a PNG: no ancestor's placement or clip applies.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - rootNodeID: The subtree's root.
    ///   - region: The region of the parent's frame the SVG frames, its `viewBox`.
    ///   - imageProvider: Loads the images image fills name.
    ///   - postIt: The words and identity colors notes, prompts and contexts are drawn with.
    /// - Returns: The SVG document's UTF-8 bytes, or `nil` when the node is not in the document.
    public static func data(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        rootNodeID: String,
        region: PenRect,
        imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) -> Data? {
        guard let node = PenLayoutEngine.node(id: rootNodeID, in: document.children) else { return nil }
        let writer = SVGWriter(
            document: document, layoutRects: layoutRects, bounds: region, imageProvider: imageProvider, postIt: postIt
        )
        let root = PenCanvasRoot(node: node, parentTransform: .identity, clips: [])
        return Data(writer.document([writer.root(root)].compactMap(\.self)).utf8)
    }
}
