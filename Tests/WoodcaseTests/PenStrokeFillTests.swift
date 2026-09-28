import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Woodcase

/// Pins that a stroke painted with a gradient or an image is clipped to the stroke's
/// outline but laid out over the node's box, whatever the alignment.
///
/// `render-stroke-fills.pen` (written by `scripts/gen-paint-geometry-fixtures`) has one
/// artboard per case: a red→blue ramp and a UV image (red = u, green = v; `images/uv-map.png`)
/// as the stroke of a rectangle under each alignment, a rounded rectangle, an ellipse, an
/// open path and per-side frames; image `fill` and `fit` modes on an outer stroke; radial
/// and angular gradients; a stack, a multiply blend and a fill opacity. The node box is
/// x 60…260, y 60…180 on every board. The references are Pen's 2x PNG exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-stroke-fills.pen --scale 2`).
struct PenStrokeFillTests {
    private static let fixture = "render-stroke-fills"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard, in document order.
    private static let artboards = [
        "rect-lin-h-inner", "rect-lin-h-center", "rect-lin-h-outer", "rect-lin-v-outer",
        "rect-lin-h-outer-radius", "rect-lin-h-center-filled",
        "rect-uv-inner", "rect-uv-center", "rect-uv-outer", "rect-uv-fill-outer", "rect-uv-fit-outer",
        "rect-radial-center", "rect-angular-center", "rect-stack", "rect-blend-multiply", "rect-grad-opacity",
        "ellipse-lin-h-outer", "ellipse-uv-center", "path-lin-h-center", "path-uv-center",
        "frame-perside-lin-h-unset", "frame-perside-lin-h-inner", "frame-perside-lin-h-outer",
        "frame-perside-uv", "frame-perside-uv-radius",
    ]

    /// Artboards whose stroke is a linear ramp, with the axis it runs along.
    private static let ramps: [(String, PenFillDomainTests.Axis)] = [
        ("rect-lin-h-inner", .x), ("rect-lin-h-center", .x), ("rect-lin-h-outer", .x),
        ("rect-lin-v-outer", .y), ("rect-lin-h-outer-radius", .x), ("rect-lin-h-center-filled", .x),
        ("ellipse-lin-h-outer", .x), ("path-lin-h-center", .x),
        ("frame-perside-lin-h-unset", .x), ("frame-perside-lin-h-inner", .x), ("frame-perside-lin-h-outer", .x),
    ]

    /// Artboards whose stroke is the UV image, stretched over the box.
    private static let uvBoards = [
        "rect-uv-inner", "rect-uv-center", "ellipse-uv-center", "path-uv-center",
        "frame-perside-uv", "frame-perside-uv-radius",
    ]

    /// The node box inside every artboard.
    private static let nodeBox = CGRect(x: 60, y: 60, width: 200, height: 120)
    private static let scale = 2

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each painted stroke matches Pen's render within MAE 0.33", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try render(artboard)
        let reference = try reference(artboard)
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Stroke fill \(artboard) MAE: \(mae)")
        // max(measured×1.5, measured+0.25) over the worst case (`ellipse-lin-h-outer`, 0.071).
        #expect(mae < 0.33, "\(artboard): MAE \(mae)")
    }

    @Test("A ramp stroke has its stops on the node box's edges, where Pen puts them", arguments: ramps)
    func rampSpansTheNodeBox(artboard: String, axis: PenFillDomainTests.Axis) throws {
        let fit = try #require(PenFillDomainTests.RampFit(render(artboard), axis: axis, scale: Self.scale))
        let pen = try #require(PenFillDomainTests.RampFit(reference(artboard), axis: axis, scale: Self.scale))
        let (start, end) = axis == .x
            ? (Self.nodeBox.minX, Self.nodeBox.maxX)
            : (Self.nodeBox.minY, Self.nodeBox.maxY)
        print("Stroke ramp \(artboard): Woodcase \(fit.stop0) → \(fit.stop1), Pen \(pen.stop0) → \(pen.stop1)")
        #expect(abs(fit.stop0 - start) < 0.5, "\(artboard): stop 0 at \(fit.stop0), box edge \(start)")
        #expect(abs(fit.stop1 - end) < 0.5, "\(artboard): stop 1 at \(fit.stop1), box edge \(end)")
        #expect(abs(fit.stop0 - pen.stop0) < 0.5, "\(artboard): stop 0 at \(fit.stop0), Pen's at \(pen.stop0)")
        #expect(abs(fit.stop1 - pen.stop1) < 0.5, "\(artboard): stop 1 at \(fit.stop1), Pen's at \(pen.stop1)")
    }

    @Test("A UV image stroke is stretched over the node box on both axes, as Pen does", arguments: uvBoards)
    func imageSpansTheNodeBox(artboard: String) throws {
        let fit = try #require(UVFit(render(artboard), scale: Self.scale))
        let pen = try #require(UVFit(reference(artboard), scale: Self.scale))
        print(
            "Stroke UV \(artboard): Woodcase u \(fit.u.stop0) → \(fit.u.stop1), v \(fit.v.stop0) → \(fit.v.stop1);"
                + " Pen u \(pen.u.stop0) → \(pen.u.stop1), v \(pen.v.stop0) → \(pen.v.stop1)"
        )
        for (name, ours, theirs) in [
            ("u0", fit.u.stop0, pen.u.stop0), ("u1", fit.u.stop1, pen.u.stop1),
            ("v0", fit.v.stop0, pen.v.stop0), ("v1", fit.v.stop1, pen.v.stop1),
        ] {
            #expect(abs(ours - theirs) < 0.5, "\(artboard) \(name): \(ours), Pen's \(theirs)")
        }
        // The image's first and last pixel centres sit half an image pixel inside the box.
        #expect(abs(fit.u.stop0 - (Self.nodeBox.minX + 200.0 / 512)) < 0.5, "\(artboard) u0 \(fit.u.stop0)")
        #expect(abs(fit.u.stop1 - (Self.nodeBox.maxX - 200.0 / 512)) < 0.5, "\(artboard) u1 \(fit.u.stop1)")
    }

    @Test("An outer image stroke in stretch or fit mode draws nothing", arguments: ["rect-uv-outer", "rect-uv-fit-outer"])
    func outerImageStrokeIsInvisible(artboard: String) throws {
        let pixels = try #require(PenFillDomainTests.RGBA(render(artboard)))
        let black = PenFillDomainTests.RGBA.Pixel(r: 0, g: 0, b: 0, a: 255)
        var drawn = 0
        for py in 0 ..< pixels.height {
            for px in 0 ..< pixels.width where pixels.pixel(px, py) != black {
                drawn += 1
            }
        }
        #expect(drawn == 0, "\(artboard): \(drawn) pixels drawn")
    }

    @Test("An outer image stroke in fill mode shows only where the covering image reaches")
    func outerFillImageStrokeShowsTheSideBands() throws {
        let pixels = try #require(PenFillDomainTests.RGBA(render("rect-uv-fill-outer")))
        // The image covers x 40…280, y 60…180: the side bands show it, top and bottom do not.
        let left = pixels.rgba(atPoint: 52, 170, scale: Self.scale)
        let right = pixels.rgba(atPoint: 268, 70, scale: Self.scale)
        #expect(left.g > 200 && left.b == 0, "left band \(left)")
        #expect(right.r > 200 && right.b == 0, "right band \(right)")
        #expect(pixels.rgba(atPoint: 160, 52, scale: Self.scale).r == 0)
        #expect(pixels.rgba(atPoint: 160, 188, scale: Self.scale).g == 0)
    }

    @Test("A line's gradient stroke is laid out over the line's box")
    func lineStrokeUsesItsBox() throws {
        let node = PenNode(
            id: "l",
            common: PenNodeCommon(),
            kind: .line(PenNode.LineData(
                stroke: .single(.gradient(PenFill.PenGradientFill(
                    gradientType: .linear,
                    rotation: .literal(270),
                    colors: [
                        PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                        PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
                    ]
                ))),
                strokeWidth: .uniform(.literal(8))
            ))
        )
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: [node]),
            layoutRects: ["l": PenRect(x: 0, y: 0, width: 200, height: 40)],
            size: CGSize(width: 200, height: 40)
        ))
        let pixels = try #require(PenFillDomainTests.RGBA(image))
        // The line runs corner to corner; at x the ramp reads x / 200 of the box.
        for x in [50, 100, 150] {
            let pixel = pixels.rgba(atPoint: x, x / 5, scale: 1)
            let expected = (Double(x) + 0.5) / 200 * 255
            #expect(pixel.a == 255 && abs(Double(pixel.b) - expected) <= 3, "x \(x): \(pixel), expected blue \(expected)")
        }
    }

    // MARK: - Helpers

    private func render(_ artboard: String) throws -> CGImage {
        try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale),
            imageProvider: Self.loadImage
        ))
    }

    private func reference(_ artboard: String) throws -> CGImage {
        try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
    }

    /// Resolves a fixture-relative image URL (`./images/uv-map.png`) against the fixtures directory.
    private static func loadImage(_ url: String) -> CGImage? {
        let file = fixturesDir.appendingPathComponent(url)
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Where a UV image's `u = 0…1` and `v = 0…1` land, fitted from the pixels it covers.
    ///
    /// The image's red is `u · 255` and its green `v · 255`, blue zero. Over pixels well
    /// inside the stroke — the mask eroded by two pixels, so anti-aliased edges drop out —
    /// a least-squares line of x against `u` and of y against `v` gives both extents.
    struct UVFit {
        struct Extent {
            let stop0: Double
            let stop1: Double
        }

        let u: Extent
        let v: Extent

        init?(_ image: CGImage, scale: Int) {
            guard let pixels = PenFillDomainTests.RGBA(image) else { return nil }
            let (w, h) = (pixels.width, pixels.height)
            let covered = (0 ..< w * h).map { i in
                let p = pixels.pixel(i % w, i / w)
                return p.b <= 3 && Int(p.r) + Int(p.g) > 30
            }
            var us: [(Double, Double)] = [], vs: [(Double, Double)] = []
            for py in 2 ..< h - 2 {
                for px in 2 ..< w - 2 {
                    let inside = (-2 ... 2).allSatisfy { dy in
                        (-2 ... 2).allSatisfy { dx in covered[(py + dy) * w + px + dx] }
                    }
                    guard inside else { continue }
                    let p = pixels.pixel(px, py)
                    let (u, v) = (Double(p.r) / 255, Double(p.g) / 255)
                    if u > 0.02, u < 0.98 { us.append((u, (Double(px) + 0.5) / Double(scale))) }
                    if v > 0.02, v < 0.98 { vs.append((v, (Double(py) + 0.5) / Double(scale))) }
                }
            }
            guard let u = Self.fit(us), let v = Self.fit(vs) else { return nil }
            self.u = u
            self.v = v
        }

        private static func fit(_ samples: [(t: Double, position: Double)]) -> Extent? {
            let n = Double(samples.count)
            let st = samples.reduce(0) { $0 + $1.t }, sp = samples.reduce(0) { $0 + $1.position }
            let stt = samples.reduce(0) { $0 + $1.t * $1.t }, stp = samples.reduce(0) { $0 + $1.t * $1.position }
            let denominator = n * stt - st * st
            guard n > 100, denominator > 0 else { return nil }
            let slope = (n * stp - st * sp) / denominator
            let stop0 = (sp - slope * st) / n
            return Extent(stop0: stop0, stop1: stop0 + slope)
        }
    }
}
