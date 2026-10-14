//
//  ShotCommand+SVG.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

extension Shot {
    /// Writes `--svg`'s output: the region the PNG would frame, as an SVG.
    ///
    /// The region and the rect= it prints are the PNG's, worked out by the same pipeline
    /// before the two part ways, so `point = (unit − gutter) / scale + origin` still maps
    /// with a scale of 1 and no gutter: an SVG unit *is* a layout point. The node is drawn
    /// in its parent's frame, as the PNG draws it (``Woodcase/SVGExporter/data(_:layoutRects:rootNodeID:region:imageProvider:postIt:)``).
    ///
    /// - Parameters:
    ///   - request: What was asked for.
    ///   - document: The expanded, resolved document.
    ///   - selection: The resolved node.
    ///   - rect: The node's layout rect.
    ///   - region: The region to frame, in the node's parent's frame.
    ///   - layoutRects: The settled rects.
    ///   - imageProvider: Loads image fills.
    ///   - url: The `.pen` file.
    ///   - reader: Who to record as having viewed the node, or `nil`.
    ///   - revision: The document revision that was read.
    /// - Returns: What to print.
    /// - Throws: ``Render/RenderError/renderFailed(_:)`` when nothing could be written, or
    ///   whatever writing the file throws.
    static func writeSVG(
        _ request: Request,
        of document: PenDocument,
        selection: ShotTargets.Selection,
        rect: PenRect,
        region: PenRect,
        layoutRects: [String: PenRect],
        imageProvider: @escaping PenRenderer.ImageProvider,
        editing url: URL,
        reader: String?,
        revision: String
    ) async throws -> ShotOutput {
        guard let data = SVGExporter.data(
            document, layoutRects: layoutRects, rootNodeID: selection.nodeID, region: region, imageProvider: imageProvider
        ) else {
            throw Render.RenderError.renderFailed(selection.nodeID)
        }
        let outputURL = URL(fileURLWithPath: request.out)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL)
        await ViewLogging.record(.shot, of: url, by: reader, revision: revision, nodes: [selection.nodeID], scope: .subtrees)

        return ShotOutput(
            node: selection.nodeID,
            scale: 1,
            rect: region,
            rects: ShotRect.list(for: selection, node: rect, outlines: []),
            pixelWidth: Int(region.width.rounded()),
            pixelHeight: Int(region.height.rounded()),
            gutterLeft: 0,
            gutterTop: 0,
            output: outputURL.path
        )
    }
}
