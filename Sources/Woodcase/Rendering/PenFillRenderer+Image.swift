import CoreGraphics
import Foundation

extension PenFillRenderer {
    /// Draws one image fill through `target`'s clip, placed by its mode and cropped by its
    /// transform inside the domain (``PenImagePlacement``).
    ///
    /// Only the placed image is drawn: where the clip reaches past it — an outer stroke,
    /// the letterbox of a `contain` image, or a stretch crop that runs off the image — nothing
    /// shows, as in Pen. A `contain` paint is also clipped to its crop box.
    ///
    /// An image the provider does not have — still downloading, or missing — draws
    /// ``PenImageLoadingPlaceholder/color`` through the whole clip instead, with the fill's
    /// opacity and blend mode; one naming no image draws nothing.
    static func renderImageFill(
        _ imageFill: PenFill.PenImageFill,
        onto target: Target,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        guard imageFill.enabled?.literalValue != false, let url = imageFill.url else { return }
        guard let cgImage = imageProvider(url) else {
            renderLoadingPlaceholder(for: imageFill, onto: target, in: context)
            return
        }
        let domain = target.domain
        guard let placed = PenImagePlacement(
            bounds: PenRect(x: domain.minX, y: domain.minY, width: domain.width, height: domain.height),
            imageSize: PenSize(width: Double(cgImage.width), height: Double(cgImage.height)),
            fill: imageFill
        ) else { return }

        PenBlendLayer.draw(imageFill.blendMode, in: context, within: target.clip.boundingBoxOfPath) {
            context.saveGState()
            defer { context.restoreGState() }

            let opacity = imageFill.opacity?.literalValue ?? 1.0
            if opacity < 1.0 {
                context.setAlpha(CGFloat(opacity))
            }
            target.applyClip(in: context)
            if let clipRect = placed.clipRect {
                context.clip(to: clipRect.cgRect)
            }

            // The image's unit square, drawn bottom-up as CG draws images into the y-down context.
            context.concatenate(placed.imageTransform.cgAffineTransform)
            context.translateBy(x: 0, y: 1)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    /// Fills `target`'s clip with ``PenImageLoadingPlaceholder/color``, its alpha scaled by
    /// the image fill's opacity, in the fill's blend mode.
    private static func renderLoadingPlaceholder(
        for imageFill: PenFill.PenImageFill,
        onto target: Target,
        in context: CGContext
    ) {
        let gray = PenImageLoadingPlaceholder.color
        let opacity = imageFill.opacity?.literalValue ?? 1.0
        var components = gray.unitComponents.map { CGFloat($0) }
        components[3] *= CGFloat(opacity)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let color = CGColor(colorSpace: space, components: components)
        else { return }
        renderSolid(color, blendMode: imageFill.blendMode, onto: target, in: context)
    }
}
