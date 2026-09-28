import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins that a fill is clipped to its outline but laid out over the node's box.
///
/// `render-fill-domains.pen` has one artboard per outline that differs from its box: a
/// donut and an even-odd path (whose holes need the even-odd rule), a hexagon and a
/// triangle (whose vertices stop short of the box), quarter-pie arcs, a curve whose
/// control points overshoot it, and a `viewBox` path drawn inside it. Each carries a
/// red→blue linear ramp. The references are Pen's 2x PNG exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-fill-domains.pen --scale 2`);
/// on every board Pen puts stop 0 and stop 1 on the node box's edges, whatever the outline.
struct PenFillDomainTests {
    private static let fixture = "render-fill-domains"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard, in document order.
    private static let artboards = [
        "donut-h", "donut-v", "evenodd-h", "hexagon-h", "triangle-v",
        "arc-h", "arc-v", "curve-v", "viewbox-h", "donut-radial",
    ]

    /// Artboards carrying a linear ramp, with the axis it runs along.
    private static let ramps: [(String, Axis)] = [
        ("donut-h", .x), ("donut-v", .y), ("evenodd-h", .x), ("hexagon-h", .x), ("triangle-v", .y),
        ("arc-h", .x), ("arc-v", .y), ("curve-v", .y), ("viewbox-h", .x),
    ]

    /// The node box inside every artboard: x 20…220, y 20…140.
    private static let nodeBox = CGRect(x: 20, y: 20, width: 200, height: 120)
    private static let scale = 2

    enum Axis { case x, y }

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each outline's fill matches Pen's render within MAE 0.39", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try render(artboard)
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Fill domain \(artboard) MAE: \(mae)")
        // max(measured×1.5, measured+0.25) over the worst case (`donut-radial`, 0.132).
        #expect(mae < 0.39, "\(artboard): MAE \(mae)")
    }

    @Test("A ramp seen through any outline has its stops on the node box's edges", arguments: ramps)
    func rampSpansTheNodeBox(artboard: String, axis: Axis) throws {
        let fit = try #require(try RampFit(render(artboard), axis: axis, scale: Self.scale))
        let (start, end) = axis == .x
            ? (Self.nodeBox.minX, Self.nodeBox.maxX)
            : (Self.nodeBox.minY, Self.nodeBox.maxY)
        #expect(abs(fit.stop0 - start) < 0.5, "\(artboard): stop 0 at \(fit.stop0), box edge \(start)")
        #expect(abs(fit.stop1 - end) < 0.5, "\(artboard): stop 1 at \(fit.stop1), box edge \(end)")
    }

    @Test("An even-odd outline draws a gradient through its ring and leaves its hole empty")
    func evenOddHoleIsEmpty() throws {
        let pixels = try #require(try RGBA(render("donut-h")))
        // The ring, left of the hole on the centre row, shows the ramp near its red end:
        // t = (40.5 - 20) / 200 ≈ 0.10.
        let ring = pixels.rgba(atPoint: 40, 80, scale: Self.scale)
        #expect(ring.r > 220 && ring.b > 15 && ring.b < 40, "ring pixel \(ring)")
        // The artboard is black; the hole shows it, not the ramp.
        let hole = pixels.rgba(atPoint: 120, 80, scale: Self.scale)
        #expect(hole.r == 0 && hole.b == 0, "hole pixel \(hole)")
    }

    @Test("An even-odd outline draws an image fill through its ring, not its hole")
    func evenOddImageFill() throws {
        let node = PenNode(
            id: "p",
            common: PenNodeCommon(),
            kind: .path(PenNode.PathData(
                geometry: "M0 0 L100 0 L100 100 L0 100 Z M25 25 L75 25 L75 75 L25 75 Z",
                fillRule: .evenodd,
                fills: .single(.image(PenFill.PenImageFill(url: "green.png")))
            ))
        )
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: [node]),
            layoutRects: ["p": PenRect(x: 0, y: 0, width: 100, height: 100)],
            size: CGSize(width: 100, height: 100),
            imageProvider: { _ in Self.solidImage(r: 0, g: 255, b: 0) }
        ))
        let pixels = try #require(RGBA(image))
        #expect(pixels.rgba(atPoint: 10, 50, scale: 1) == .init(r: 0, g: 255, b: 0, a: 255))
        #expect(pixels.alpha(atPoint: 50, 50, scale: 1) == 0)
    }

    @Test("A gradient drawn through a clip narrower than its domain keeps the domain's ramp")
    func clipNarrowerThanDomain() throws {
        let context = try #require(Self.context(width: 200, height: 40))
        // y down, as `PenRenderer` draws.
        context.translateBy(x: 0, y: 40)
        context.scaleBy(x: 1, y: -1)
        let ramp = PenFills.single(.gradient(PenFill.PenGradientFill(
            gradientType: .linear,
            rotation: .literal(270),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
            ]
        )))
        PenFillRenderer.renderFills(
            ramp,
            clip: CGPath(rect: CGRect(x: 80, y: 0, width: 40, height: 40), transform: nil),
            fillRule: .winding,
            domain: CGRect(x: 0, y: 0, width: 200, height: 40),
            in: context
        )
        let image = try #require(context.makeImage())
        let pixels = try #require(RGBA(image))
        // Outside the clip: nothing.
        #expect(pixels.alpha(atPoint: 60, 20, scale: 1) == 0)
        #expect(pixels.alpha(atPoint: 140, 20, scale: 1) == 0)
        // Inside it, t is the pixel centre's fraction of the 200-pt domain, not of the 40-pt clip.
        for x in [80, 90, 100, 119] {
            let expected = (Double(x) + 0.5) / 200 * 255
            let blue = Double(pixels.rgba(atPoint: x, 20, scale: 1).b)
            #expect(abs(blue - expected) <= 2, "x \(x): blue \(blue), expected \(expected)")
        }
    }

    // MARK: - Helpers

    private func render(_ artboard: String) throws -> CGImage {
        try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
        ))
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    private static func solidImage(r: UInt8, g: UInt8, b: UInt8) -> CGImage? {
        guard let context = context(width: 2, height: 2) else { return nil }
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()
    }

    /// An image's pixels as 8-bit premultiplied sRGB RGBA, row 0 at the top.
    struct RGBA {
        struct Pixel: Equatable {
            let r: UInt8, g: UInt8, b: UInt8, a: UInt8
        }

        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &buffer, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func pixel(_ px: Int, _ py: Int) -> Pixel {
            let o = (py * width + px) * 4
            return Pixel(r: bytes[o], g: bytes[o + 1], b: bytes[o + 2], a: bytes[o + 3])
        }

        /// The pixel under the point (`x`, `y`) in points, at `scale` pixels per point.
        func rgba(atPoint x: Int, _ y: Int, scale: Int) -> Pixel {
            pixel(x * scale, y * scale)
        }

        func alpha(atPoint x: Int, _ y: Int, scale: Int) -> UInt8 {
            rgba(atPoint: x, y, scale: scale).a
        }
    }

    /// Where a red→blue ramp's stops sit along one axis, fitted from the covered pixels.
    ///
    /// On a fully covered pixel of the ramp `R + B = 255` and `G = 0`, so `t = B / 255`.
    /// A least-squares line of position (points, pixel centres) against `t`, over pixels
    /// strictly inside the ramp, gives the positions of `t = 0` and `t = 1`.
    struct RampFit {
        let stop0: Double
        let stop1: Double

        init?(_ image: CGImage, axis: Axis, scale: Int) {
            guard let pixels = RGBA(image) else { return nil }
            var n = 0.0, st = 0.0, sp = 0.0, stt = 0.0, stp = 0.0
            for py in 0 ..< pixels.height {
                for px in 0 ..< pixels.width {
                    let p = pixels.pixel(px, py)
                    guard p.a == 255, p.g <= 3, abs(Int(p.r) + Int(p.b) - 255) <= 3 else { continue }
                    let t = Double(p.b) / 255
                    guard t > 0.02, t < 0.98 else { continue }
                    let position = (Double(axis == .x ? px : py) + 0.5) / Double(scale)
                    n += 1; st += t; sp += position; stt += t * t; stp += t * position
                }
            }
            let denominator = n * stt - st * st
            guard n > 100, denominator > 0 else { return nil }
            let slope = (n * stp - st * sp) / denominator
            stop0 = (sp - slope * st) / n
            stop1 = stop0 + slope
        }
    }
}
