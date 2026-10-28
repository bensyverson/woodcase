import CoreGraphics

/// Draws silhouette ink through an offscreen mask, as one image.
///
/// An outer shadow draws its silhouette far outside the context's clip and lets the shadow
/// fall back (``PenEffectRenderer/renderOuterShadows(_:bounds:in:silhouette:)``). Two things
/// cannot be done there directly. A clip set there meets the context's own clip in nothing
/// and erases the ink, so a clipping frame's descendants could not be cut to it. And each
/// piece of ink drawn casts a shadow of its own, so where a frame's or a group's pieces meet
/// their shadows would add up, darker than the one shadow Pen casts from their union. Both
/// are solved by drawing the ink into a bitmap — at the context's device scale, aligned to
/// its device pixels, clipped there when asked — and drawing the bitmap back as one image,
/// which casts one shadow wherever it lands.
enum PenSilhouetteMask {
    /// The largest side, in pixels, a mask is drawn at; a larger one is drawn coarser.
    static let maxSide: CGFloat = 8192

    /// Draws what `ink` draws within `bounds`, cut to `clip` when one is given, into
    /// `context` as one image.
    ///
    /// - Parameters:
    ///   - bounds: Contains everything `ink` draws that counts, in the context's current space.
    ///   - clip: The outline to cut the ink to, in the same space, or `nil`.
    ///   - context: The context to draw into.
    ///   - ink: Draws the silhouette into the context it is given, in the same space as
    ///     `context`'s current one, y down.
    static func draw(within bounds: CGRect, clip: CGPath? = nil, in context: CGContext, ink: (CGContext) -> Void) {
        let box = clip.map { $0.boundingBoxOfPath.intersection(bounds) } ?? bounds
        guard !box.isNull, !box.isEmpty, box.width.isFinite, box.height.isFinite else { return }
        let area = context.convertToUserSpace(context.convertToDeviceSpace(box).integral)
        let scale = min(
            PenEffectRenderer.deviceScale(of: context),
            maxSide / max(area.width, 1), maxSide / max(area.height, 1)
        )
        let width = Int((area.width * scale).rounded(.up))
        let height = Int((area.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let mask = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }
        // y down, as the renderer draws: the area's top-left at the bitmap's top-left.
        mask.translateBy(x: 0, y: CGFloat(height))
        mask.scaleBy(x: scale, y: -scale)
        mask.translateBy(x: -area.minX, y: -area.minY)
        if let clip {
            mask.addPath(clip)
            mask.clip()
        }
        ink(mask)
        guard let image = mask.makeImage() else { return }

        context.saveGState()
        let ctm = context.ctm
        context.interpolationQuality = ctm.b == 0 && ctm.c == 0 ? .none : .default
        // Undo the y-down flip for the image, which draws its bottom row first.
        context.translateBy(x: 0, y: area.minY + area.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: area)
        context.restoreGState()
    }
}
