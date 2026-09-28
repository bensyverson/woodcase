import CoreGraphics

extension PenEffectRenderer {
    /// Replaces the pixels inside a node's shape with the blurred backdrop behind it.
    ///
    /// The backdrop is what the canvas already holds under the node. Only the node's own
    /// region is captured — its device bounds plus the three sigmas of kernel that reach
    /// into it — and blurred with ``PenGaussianBlur`` at sigma `radius / 2` points on the
    /// encoded sRGB values, clamping at the capture's edges, as Pen does. The result is
    /// drawn back clipped to the node's shape, so corner radii, ellipses, paths and every
    /// ancestor clip hold.
    ///
    /// Nothing is drawn when the effect is disabled or has no radius, when the node has no
    /// visible fill (``PenFills/hasVisiblePaint``: Pen's fill gate, which Woodcase copies),
    /// or when the context is not bitmap-backed — a PDF has no pixels to blur.
    ///
    /// Pen 1.2.14 also draws no background blur on a node below opacity 1. Woodcase does not
    /// copy that: the blur is drawn inside the node's opacity layer like the rest of it.
    ///
    /// - Parameters:
    ///   - effect: The background blur effect parameters.
    ///   - fills: The node's fills, for the fill gate.
    ///   - clipPath: The node's shape path, in the current coordinate system.
    ///   - context: The main rendering context.
    static func renderBackgroundBlur(
        _ effect: PenEffect.PenBackgroundBlurEffect,
        fills: PenFills?,
        clipPath: CGPath,
        in context: CGContext
    ) {
        let radius = CGFloat(effect.radius?.literalValue ?? 0)
        guard effect.enabled?.literalValue != false, radius > 0,
              fills?.hasVisiblePaint == true,
              let canvas = context.makeImage()
        else { return }

        let sigma = radius * deviceScale(of: context) / 2
        let canvasRect = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        let reach = ceil(sigma * 3)
        let region = clipPath.boundingBoxOfPath.applying(context.ctm)
            .insetBy(dx: -reach, dy: -reach).integral
            .intersection(canvasRect)
        guard !region.isEmpty else { return }

        // Device space runs bottom-up; the canvas image's rows run top-down.
        let crop = CGRect(
            x: region.minX, y: canvasRect.height - region.maxY,
            width: region.width, height: region.height
        )
        guard let backdrop = canvas.cropping(to: crop),
              let blurred = PenGaussianBlur.blur(backdrop, sigma: sigma, edges: .extend)
        else { return }

        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        // Back to device pixels; the clip, already rasterised, stays where it was. An image
        // drawn into a bottom-up rect lands upright, so no flip is needed here.
        context.concatenate(context.ctm.inverted())
        context.setBlendMode(.copy)
        context.draw(blurred, in: region)
        context.restoreGState()
    }
}
