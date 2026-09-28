//
//  ShotRegionRenderer.swift
//  WoodcaseCommandCore
//

import CoreGraphics
import Foundation
import Woodcase

/// Renders one node's subtree into an image covering a chosen *region* of it.
///
/// ``Woodcase/PenRenderer/render(_:layoutRects:size:scale:colorSpace:rootNodeID:overrides:imageProvider:)``
/// always frames a subtree at its own rect: it makes a bitmap the node's size and
/// translates by the node's origin. That is the whole node, every time, which is exactly
/// what `--crop` must not do — a tile of a tall board has to be rendered at the tile's
/// size and the tile's origin, or the intermediate bitmap is the whole board again and
/// `--scale 4` on a 20,000-point board asks for gigabytes.
///
/// So this drives the renderer's *other* public entry point,
/// ``Woodcase/PenRenderer/render(_:layoutRects:into:rootNodeID:overrides:imageProvider:)``,
/// which draws into a context the caller has positioned. The transform below is the
/// same one the sizing entry point applies, with the region's origin substituted for the
/// node's — which is why an uncropped run through here is byte-identical to what `shot`
/// rendered before `--crop` existed, and why there is only one path to keep true.
enum ShotRegionRenderer {
    /// Renders `region` of `node`'s subtree.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - node: The id of the subtree root to draw, post-expansion.
    ///   - region: The rectangle to cover, in the same coordinate space as
    ///     ``Woodcase/PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` returns —
    ///     the node's own rect for a whole-node shot, the crop for a tiled one.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - scale: Pixels per layout point.
    ///   - imageProvider: How to load an image fill.
    /// - Returns: The image, or `nil` when the region is empty at this scale or the
    ///   bitmap could not be allocated.
    static func image(
        of document: PenDocument,
        node: String,
        region: PenRect,
        layoutRects: [String: PenRect],
        scale: Double,
        imageProvider: @escaping PenRenderer.ImageProvider
    ) -> CGImage? {
        // Rounded, not truncated: a region already grown to whole pixels
        // (`PenRect/grownToWholePixels(at:)`) times its own scale lands within floating-
        // point noise of a whole number, and truncating that noise away is how a 299 px
        // painted extent rendered 298 (`PenPaintedExtentProbeTests`'s sibling at the CLI,
        // `ShotCommandTests.extentPaintedMatchesPensExportPixelSize`).
        let pixelWidth = Int((region.width * scale).rounded())
        let pixelHeight = Int((region.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: pixelWidth * 4,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }

        if scale != 1 {
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        }
        // CoreGraphics counts up from the bottom-left; .pen counts down from the
        // top-left. Flip within the region's own height, then slide the region's origin
        // to (0, 0) so the node draws where the crop says it should.
        context.translateBy(x: 0, y: CGFloat(region.height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-region.x), y: CGFloat(-region.y))

        PenRenderer.render(
            document, layoutRects: layoutRects, into: context,
            rootNodeID: node, imageProvider: imageProvider
        )
        return context.makeImage()
    }
}
