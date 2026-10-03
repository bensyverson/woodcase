import CoreGraphics
import Foundation

extension PenFillRenderer {
    /// Draws one image fill through `target`'s clip, placed by its mode inside the domain.
    ///
    /// Only the placed image is drawn: where the clip reaches past it — an outer stroke,
    /// or the letterbox of a `contain` image — nothing shows, as in Pen.
    static func renderImageFill(
        _ imageFill: PenFill.PenImageFill,
        onto target: Target,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        guard imageFill.enabled?.literalValue != false else { return }
        guard let url = imageFill.url, let cgImage = imageProvider(url) else { return }

        let drawRect = imageRect(
            placement: imageFill.mode?.placement ?? .stretch,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            in: target.domain
        )

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

        // CG draws images bottom-up; the context is flipped to y-down.
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: drawRect.size))
    }

    /// Where an image of `imageSize` lands inside `domain` under `placement`.
    ///
    /// - `stretch` fills the domain exactly, ignoring the aspect ratio.
    /// - `cover` scales to cover the domain, centered, overflowing on one axis.
    /// - `contain` scales to fit inside the domain, centered, leaving bands on one axis.
    static func imageRect(placement: PenImageFillMode.Placement, imageSize: CGSize, in domain: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return domain }
        let scaleX = domain.width / imageSize.width
        let scaleY = domain.height / imageSize.height
        let scale: CGFloat
        switch placement {
        case .stretch:
            return domain
        case .cover:
            scale = max(scaleX, scaleY)
        case .contain:
            scale = min(scaleX, scaleY)
        }
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: domain.midX - width / 2, y: domain.midY - height / 2, width: width, height: height)
    }
}
