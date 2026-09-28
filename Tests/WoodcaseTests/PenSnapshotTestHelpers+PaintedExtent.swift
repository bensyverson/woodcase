//
//  PenSnapshotTestHelpers+PaintedExtent.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
@testable import Woodcase

extension PenSnapshotTestHelpers {
    /// Renders one top-level artboard of a fixture framed as Pen's export frames it: on its
    /// painted extent, from its exact corner, grown to whole pixels at `scale`.
    ///
    /// Pen's PNG export is bounded by what the node paints — its strokes, shadows, blurs
    /// and unclipped children — not by its layout rect, so a reference image's origin is
    /// the painted extent's corner, not the node's. This places the render there, so a new
    /// fixture needs no hand-measured overflow offset
    /// (``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``).
    ///
    /// - Parameters:
    ///   - artboard: The artboard's `name`, or its id when it has none.
    ///   - fixture: The fixture's file name without `.pen`.
    ///   - fixturesDir: The directory holding the fixture.
    ///   - scale: The render scale — the reference's.
    ///   - imageProvider: Resolves the fixture's image fills; none by default.
    /// - Returns: The image, or `nil` when the artboard is missing or the render fails.
    static func renderPaintedArtboard(
        named artboard: String,
        in fixture: String,
        fixturesDir: URL,
        scale: CGFloat,
        imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil }
    ) throws -> CGImage? {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        let resolved = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        guard let node = resolved.children.first(where: { $0.common.name == artboard || $0.id == artboard }) else {
            return nil
        }
        let rects = PenLayoutEngine.layout(resolved)
        guard let rect = rects[node.id] else { return nil }
        let region = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
            .grownToWholePixels(at: Double(scale))
        return renderRegion(region, of: node.id, in: resolved, layoutRects: rects, scale: scale, imageProvider: imageProvider)
    }

    /// Renders `region` of a node's subtree, in the node's parent's coordinates, at `scale`.
    ///
    /// - Parameters:
    ///   - region: The rectangle the image covers.
    ///   - nodeID: The subtree root.
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects.
    ///   - scale: Pixels per point.
    ///   - imageProvider: Resolves image fills.
    /// - Returns: The image, or `nil` when the bitmap cannot be made.
    static func renderRegion(
        _ region: PenRect,
        of nodeID: String,
        in document: PenDocument,
        layoutRects: [String: PenRect],
        scale: CGFloat,
        imageProvider: @escaping PenRenderer.ImageProvider = { _ in nil }
    ) -> CGImage? {
        let width = Int((region.width * scale).rounded())
        let height = Int((region.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: CGFloat(region.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-region.x), y: CGFloat(-region.y))
        PenRenderer.render(
            document, layoutRects: layoutRects, into: context, rootNodeID: nodeID, imageProvider: imageProvider
        )
        return context.makeImage()
    }
}
