//
//  ShotOverlay.swift
//  WoodcaseCommandCore
//

import CoreGraphics
import Foundation
import PixelPeeper
import Woodcase

/// Draws `shot`'s annotations onto a rendered image: the boxes `--outline` asked for,
/// then the ruler `--grid` asked for.
///
/// The whole point of both flags is that an agent reading a screenshot cannot count
/// pixels — it reads landmarks. A box says *this rectangle is the node you named*, and
/// a numbered gutter says *this pixel is that layout point*, so the picture answers in
/// the same coordinates the rest of the CLI speaks.
///
/// ## Order matters, twice
///
/// The outlines go on **before** the grid, because the grid moves the image: it
/// returns a *larger* picture with the original blitted in at the gutters' offset, so
/// a box drawn afterwards would need the gutter added to every coordinate. Both go on
/// **after** `shot` has fitted the render to `--max`, because the gutter's digits are
/// chrome — scaled down with the image they would be unreadable, and the ruler would
/// be measuring the wrong thing.
///
/// The consequence a caller has to know about is that `--grid` makes the PNG bigger
/// than `--max`, by exactly ``Annotated/leftGutter`` and ``Annotated/topGutter``.
/// ``ShotOutput`` reports both so a pixel can still be mapped back to a point.
enum ShotOverlay {
    /// One box to draw: where the node is, and what to call it.
    struct Target: Friendly {
        /// The node's layout rect, in points, in the same frame as the rendered
        /// node's own rect.
        let rect: PenRect

        /// The name printed in the box's tag — the node's own name, or its `#id`
        /// marker when it has none.
        let label: String
    }

    /// An annotated image and the offset the grid pushed the render to.
    ///
    /// The gutters are `0` when no grid was drawn, which keeps one mapping formula
    /// true of every shot: `point = (pixel − gutter) / scale + origin`.
    struct Annotated {
        /// The image to write.
        let image: CGImage

        /// How many pixels the left gutter added, `0` without `--grid`.
        let leftGutter: Int

        /// How many pixels the top gutter added, `0` without `--grid`.
        let topGutter: Int
    }

    /// Why an overlay could not be drawn.
    ///
    /// PixelPeeper's own failures — a non-positive scale, a bitmap it could not
    /// allocate — arrive as `PixelPeeperError` and are reported as they are; this
    /// covers the one step that happens on this side of the seam.
    enum OverlayError: Error, CustomStringConvertible, Equatable {
        /// The annotated pixels could not be turned back into a `CGImage`.
        case imageUnavailable(width: Int, height: Int)

        /// A sentence naming the size that could not be rebuilt.
        var description: String {
            switch self {
            case let .imageUnavailable(width, height):
                "Could not rebuild a \(width)×\(height) image from the annotated pixels."
            }
        }
    }

    /// Annotates a rendered image.
    ///
    /// - Parameters:
    ///   - image: The rendered node, already fitted to `--max`.
    ///   - targets: The boxes to draw, in layout points. Empty draws none.
    ///   - grid: Whether to add the numbered gutter.
    ///   - pixelsPerPoint: The scale the render actually landed on — image pixels per
    ///     layout point. Not the scale that was asked for: `shot` never enlarges, so a
    ///     node smaller than `--max` renders at 1 however large `--max` was.
    ///   - origin: The rendered node's own layout origin, which
    ///     ``PenRenderer/render(_:layoutRects:size:scale:rootNodeID:overrides:imageProvider:)``
    ///     subtracted before drawing. Every rect and every ruler label is measured
    ///     from it, so the numbers are the document's coordinates and not the crop's.
    /// - Returns: The annotated image and its gutters.
    /// - Throws: ``OverlayError/imageUnavailable(width:height:)``, or whatever
    ///   PixelPeeper throws.
    static func apply(
        to image: CGImage,
        outlining targets: [Target],
        grid: Bool,
        pixelsPerPoint: Double,
        origin: CGPoint
    ) throws -> Annotated {
        guard grid || !targets.isEmpty else {
            return Annotated(image: image, leftGutter: 0, topGutter: 0)
        }

        var annotated = try PixelImage(cgImage: image)
        if !targets.isEmpty {
            annotated = try annotated.withOutlines(
                targets.map { Outline(rect: $0.rect.cgRect, label: $0.label) },
                pixelsPerPoint: pixelsPerPoint,
                origin: origin
            )
        }

        var leftGutter = 0
        var topGutter = 0
        if grid {
            let options = GridOptions()
            let layout = GridLayout(
                imageWidth: annotated.width, imageHeight: annotated.height,
                options: options, pixelsPerPoint: pixelsPerPoint, origin: origin
            )
            leftGutter = layout.leftGutter
            topGutter = layout.topGutter
            annotated = try annotated.withGrid(
                options, pixelsPerPoint: pixelsPerPoint, origin: origin
            )
        }

        return try Annotated(
            image: coreGraphicsImage(from: annotated),
            leftGutter: leftGutter,
            topGutter: topGutter
        )
    }

    /// Rebuilds a `CGImage` from PixelPeeper's raw RGBA bytes.
    ///
    /// PixelPeeper reads a `CGImage` but only writes a PNG file, and `shot`'s PNG has
    /// to go out through ``ImageExporter`` like every other image the CLI produces —
    /// so the bytes come back across here. The layout is the one `PixelImage` promises:
    /// row-major RGBA, premultiplied, sRGB.
    ///
    /// - Parameter image: The annotated pixels.
    /// - Returns: The same pixels as a Core Graphics image.
    /// - Throws: ``OverlayError/imageUnavailable(width:height:)`` if the bitmap
    ///   context cannot be built or will not yield an image.
    private static func coreGraphicsImage(from image: PixelImage) throws -> CGImage {
        var pixels = image.pixels
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        // The context reads through the buffer, so the pointer must outlive the
        // `makeImage()` call — hence the closure rather than an inout `&pixels`,
        // which is valid only for the duration of the initializer.
        let made: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )?.makeImage()
        }
        guard let made else {
            throw OverlayError.imageUnavailable(width: image.width, height: image.height)
        }
        return made
    }
}
