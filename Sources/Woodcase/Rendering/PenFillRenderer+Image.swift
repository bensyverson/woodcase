import CoreGraphics
import Foundation

extension PenFillRenderer {
    /// Draws one image fill through `target`'s clip, placed by its mode and cropped by its
    /// transform inside the domain (``PenImagePlacement``).
    ///
    /// Only the placed image is drawn: where the clip reaches past it — an outer stroke,
    /// the letterbox of a `contain` image, or a stretch crop that runs off the image — nothing
    /// shows, as in Pen. A `contain` paint is also clipped to its crop box.
    static func renderImageFill(
        _ imageFill: PenFill.PenImageFill,
        onto target: Target,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        guard imageFill.enabled?.literalValue != false else { return }
        guard let url = imageFill.url, let cgImage = imageProvider(url) else { return }
        let domain = target.domain
        guard let placed = PenImagePlacement(
            bounds: PenRect(x: domain.minX, y: domain.minY, width: domain.width, height: domain.height),
            imageSize: PenSize(width: Double(cgImage.width), height: Double(cgImage.height)),
            fill: imageFill
        ) else { return }

        context.saveGState()
        defer { context.restoreGState() }

        if let blendMode = imageFill.blendMode {
            context.setBlendMode(blendMode.cgBlendMode)
        }
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
