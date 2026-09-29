import CoreGraphics
import Foundation

extension PenFillRenderer {
    /// The fewest raster pixels per point a mesh gets in a context that is not a bitmap.
    ///
    /// A PDF context's device space is its point space, so the device scale alone would
    /// rasterize at 1x, which looks soft when the page is zoomed. Pen's own PDF export
    /// embeds its mesh at 2x, and Woodcase matches it (Ben's ruling, 2026-09-26).
    static let minimumVectorMeshScale: CGFloat = 2

    /// Draws one mesh gradient fill through `target`'s clip, laid out over its domain.
    ///
    /// CoreGraphics has no mesh primitive, so the mesh core rasterizes the fill
    /// (<doc:PenMeshGradients>) at the context's device resolution — at least
    /// ``minimumVectorMeshScale`` in a PDF — and the raster is drawn over the domain, the
    /// node's box, never the clip's bounds. The fill's opacity and blend mode apply when
    /// it is composited. A mesh Pen would not draw (a missing field, a count that is not
    /// `columns × rows`) draws nothing.
    static func renderMeshGradient(
        _ mesh: PenFill.PenMeshGradientFill,
        onto target: Target,
        in context: CGContext
    ) {
        guard mesh.enabled?.literalValue != false,
              let grid = try? PenMeshGrid(mesh),
              let placed = meshImage(grid, domain: target.domain, in: context)
        else { return }

        context.saveGState()
        defer { context.restoreGState() }

        if let blendMode = mesh.blendMode {
            context.setBlendMode(blendMode.cgBlendMode)
        }
        let opacity = mesh.opacity?.literalValue ?? 1.0
        if opacity < 1.0 {
            context.setAlpha(CGFloat(opacity))
        }
        target.applyClip(in: context)

        // CG draws images bottom-up; the context is flipped to y-down.
        context.translateBy(x: placed.rect.minX, y: placed.rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(placed.image, in: CGRect(origin: .zero, size: placed.rect.size))
    }

    /// Rasterizes `grid` for `domain` at the context's resolution.
    ///
    /// The raster covers whole pixels, so its rectangle starts at the domain's origin and
    /// reaches up to one pixel past its far edges; the mesh itself is tessellated at the
    /// domain's exact size and leaves that sliver transparent. That keeps one raster pixel
    /// to one device pixel rather than stretching the mesh by a fraction.
    ///
    /// - Returns: The image and the rectangle, in the context's user space, to draw it in;
    ///   `nil` for an empty domain.
    static func meshImage(
        _ grid: PenMeshGrid,
        domain: CGRect,
        in context: CGContext
    ) -> (image: CGImage, rect: CGRect)? {
        let scale = meshRasterScale(in: context)
        let width = Double(domain.width * scale.width)
        let height = Double(domain.height * scale.height)
        // A hair of tolerance so a box that is a whole number of pixels in exact
        // arithmetic does not gain a column to float error.
        let pixelWidth = Int((width - 1e-6).rounded(.up))
        let pixelHeight = Int((height - 1e-6).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let tessellation = PenMeshTessellator().tessellate(grid, width: width, height: height)
        let raster = PenMeshRasterizer.rasterize(tessellation, width: pixelWidth, height: pixelHeight)
        guard let image = cgImage(raster) else { return nil }
        let rect = CGRect(
            x: domain.minX,
            y: domain.minY,
            width: CGFloat(pixelWidth) / scale.width,
            height: CGFloat(pixelHeight) / scale.height
        )
        return (image, rect)
    }

    /// Device pixels per user-space unit along each axis of the context.
    ///
    /// A bitmap context answers its own device scale, whatever the rotation. Any other
    /// context — a PDF — answers at least ``minimumVectorMeshScale``.
    static func meshRasterScale(in context: CGContext) -> CGSize {
        let transform = context.userSpaceToDeviceSpaceTransform
        let scaleX = hypot(transform.a, transform.b)
        let scaleY = hypot(transform.c, transform.d)
        // Only a bitmap context has a pixel width; a PDF context reports zero.
        guard context.width == 0 else { return CGSize(width: scaleX, height: scaleY) }
        return CGSize(
            width: max(scaleX, minimumVectorMeshScale),
            height: max(scaleY, minimumVectorMeshScale)
        )
    }

    /// Wraps a mesh raster's premultiplied sRGB bytes as a `CGImage`.
    private static func cgImage(_ raster: PenMeshRaster) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(raster.pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: raster.bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
