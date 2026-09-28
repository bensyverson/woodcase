import CoreGraphics
import Foundation
import ImageIO
import PixelPeeper
@testable import Woodcase

/// Helpers for comparing rendered images against reference PNGs.
enum PenSnapshotTestHelpers {
    /// Computes the mean absolute error (MAE) between two images, in 8-bit channel steps.
    ///
    /// Both images are decoded by PixelPeeper into premultiplied sRGB RGBA8 and compared
    /// with ``ImageComparator``; the figure is its ``ImageComparisonResult/maeSteps``, the
    /// average absolute difference over every channel (alpha included) of every pixel:
    /// - 0.0 means identical
    /// - 255.0 means maximally different
    ///
    /// If the images have different dimensions, each is **resampled** — drawn whole,
    /// scaled — onto the smaller width and the smaller height before comparing
    /// (``PixelImage/init(cgImage:width:height:)``). It is not a crop: a 2× render
    /// measured against a 1× reference depends on the downscale, and so do pinned
    /// figures for renders a pixel or two off their reference's size (a WebView page
    /// taller than the Woodcase-computed rect). An image with no pixels, or one that
    /// cannot be decoded, scores 255.
    static func meanAbsoluteError(between rendered: CGImage, and reference: CGImage) -> Double {
        let width = min(rendered.width, reference.width)
        let height = min(rendered.height, reference.height)

        guard width > 0, height > 0 else { return 255.0 }

        var watch = PhaseStopwatch("mae:\(width)x\(height)")
        guard let renderedPixels = try? PixelImage(cgImage: rendered, width: width, height: height),
              let referencePixels = try? PixelImage(cgImage: reference, width: width, height: height)
        else {
            return 255.0
        }
        watch.lap("extract")
        guard let result = try? ImageComparator.compare(renderedPixels, referencePixels) else { return 255.0 }
        watch.lap("diff")
        watch.total()

        return result.maeSteps.value
    }

    /// Renders one top-level artboard of a fixture through the full pipeline.
    ///
    /// - Parameters:
    ///   - artboard: The artboard's `name`.
    ///   - fixture: The fixture's file name without `.pen`.
    ///   - fixturesDir: The directory holding the fixture.
    ///   - scale: The render scale.
    ///   - imageProvider: Resolves the fixture's image fills; none by default.
    /// - Returns: The artboard's image, or `nil` when the artboard is missing or the render fails.
    static func renderArtboard(
        named artboard: String,
        in fixture: String,
        fixturesDir: URL,
        scale: CGFloat,
        imageProvider: PenRenderer.ImageProvider = { _ in nil }
    ) throws -> CGImage? {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        let resolved = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        guard let node = resolved.children.first(where: { $0.common.name == artboard }) else { return nil }
        let rects = PenLayoutEngine.layout(resolved)
        guard let rect = rects[node.id] else { return nil }
        return PenRenderer.render(
            resolved, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: scale, rootNodeID: node.id, imageProvider: imageProvider
        )
    }

    /// The names of a fixture's top-level artboards, in document order.
    static func artboardNames(in fixture: String, fixturesDir: URL) throws -> [String] {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        return try PenParser.parse(data).children.compactMap(\.common.name)
    }

    /// Loads a PNG from the fixtures directory.
    static func loadFixtureImage(named name: String, fixturesDir: URL) -> CGImage? {
        let url = fixturesDir.appendingPathComponent("\(name).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return image
    }
}
