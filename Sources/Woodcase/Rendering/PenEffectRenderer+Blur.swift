import CoreGraphics

extension PenEffectRenderer {
    /// Renders a node with a layer blur: its whole subtree blurred as one image.
    ///
    /// Draws the node into an offscreen buffer at the context's resolution, padded by three
    /// sigmas, blurs it with ``PenGaussianBlur`` at sigma `radius / 2` points — `radius ·
    /// scale / 2` pixels, so the blur looks the same at every render scale — and composites
    /// the result back. A disabled or zero-radius blur, or one whose buffer cannot be made,
    /// draws the node unblurred.
    ///
    /// - Parameters:
    ///   - blur: The blur effect parameters.
    ///   - rect: The node's box in the context's space: zero-origin for most nodes, a group's
    ///     children's union — measured from its anchor, so anywhere — for a group.
    ///   - overflow: How far, in points, the node draws outside `rect` — its outer shadows'
    ///     reach — so the buffer holds them before they are blurred.
    ///   - context: The main rendering context.
    ///   - draw: A closure that draws the node content into a provided context.
    static func renderBlur(
        _ blur: PenEffect.PenBlurEffect,
        rect: PenRect,
        overflow: CGFloat = 0,
        in context: CGContext,
        draw: (CGContext) -> Void
    ) {
        let radius = CGFloat(blur.radius?.literalValue ?? 0)
        guard blur.enabled?.literalValue != false, radius > 0 else {
            draw(context)
            return
        }

        let scale = deviceScale(of: context)
        let sigma = radius * scale / 2
        let padding = ceil(sigma * 3 + max(0, overflow) * scale)
        let offscreenWidth = Int(ceil(CGFloat(rect.width) * scale + padding * 2))
        let offscreenHeight = Int(ceil(CGFloat(rect.height) * scale + padding * 2))

        guard let offscreen = CGContext(
            data: nil,
            width: offscreenWidth,
            height: offscreenHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            draw(context)
            return
        }

        // Scale and flip the offscreen buffer to the renderer's y-down points, with the node
        // drawn `padding` pixels in from the top-left.
        offscreen.scaleBy(x: scale, y: scale)
        offscreen.translateBy(x: 0, y: CGFloat(rect.height) + padding * 2 / scale)
        offscreen.scaleBy(x: 1, y: -1)
        offscreen.translateBy(x: padding / scale - CGFloat(rect.x), y: padding / scale - CGFloat(rect.y))
        draw(offscreen)

        guard let content = offscreen.makeImage(),
              let blurred = PenGaussianBlur.blur(content, sigma: sigma, edges: .transparent)
        else {
            draw(context)
            return
        }

        // CGContext.draw puts an image's first row at the rect's maximum y, so un-flip
        // locally to land it upright in the y-down space.
        let drawRect = CGRect(
            x: CGFloat(rect.x) - padding / scale,
            y: -CGFloat(rect.y) - (CGFloat(offscreenHeight) - padding) / scale,
            width: CGFloat(offscreenWidth) / scale,
            height: CGFloat(offscreenHeight) / scale
        )
        context.saveGState()
        context.scaleBy(x: 1, y: -1)
        context.draw(blurred, in: drawRect)
        context.restoreGState()
    }
}
