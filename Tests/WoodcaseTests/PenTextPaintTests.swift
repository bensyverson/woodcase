import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins that a text node's paint is laid out over the node's box and shown through its glyphs.
///
/// `render-text-fills.pen` holds the text boards and twins of the text-and-stroke fills
/// report (`project/2026-09-26-text-and-stroke-fills.md`): each `txt-*` board is one text
/// node carrying a red→blue linear ramp; each `twin-*` board puts a 400×120 text node above
/// a 400×120 rectangle with the same fills, 140 pt lower. The references are Pen's 2x PNG
/// exports (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-text-fills.pen --scale 2`).
///
/// The gates are geometric, because Woodcase measures text differently from Pen (about 5%
/// on these faces): the fitted ramp's stops must sit on the node box's edges, and a twin's
/// text must show the same colour its rectangle shows at the same place in the box. The MAE
/// against Pen is printed and held to a ceiling, but it is bounded by the glyph mismatch.
struct PenTextPaintTests {
    /// Every board sets Inter; without it they measure the fallback face, not the paint.
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixture = "render-text-fills"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale = 2

    typealias Axis = PenFillDomainTests.Axis

    /// Text boards carrying a linear ramp, with the axis it runs along.
    private static let ramps: [(String, Axis)] = [
        ("txt-lin-h-auto", .x), ("txt-lin-v-auto", .y), ("txt-lin-h-fixed-left", .x),
        ("txt-lin-h-fixed-center", .x), ("txt-lin-v-multiline", .y), ("txt-lin-h-ragged", .x),
        ("txt-lin-v-fwh-top", .y), ("txt-lin-v-fwh-middle", .y), ("icon-grad", .x),
    ]

    /// Boards whose glyphs span too little of the box along the ramp for an end-stop fit: one
    /// 72 pt line in a 300 pt box puts the fitted stops five times further out than the data,
    /// and a level of quantisation there moves them by a point (Pen's own render of
    /// `txt-lin-v-fwh-middle` fits to 39.96 → 340.02 only because its ramp dithers less).
    /// The per-band residual still pins the domain on these.
    private static let shortSpans: Set<String> = ["txt-lin-v-fwh-top", "txt-lin-v-fwh-middle"]

    /// Every twin: its text half must show what its rectangle half shows.
    private static let twins = [
        "twin-lin-h", "twin-lin-diag", "twin-radial", "twin-angular",
        "twin-image-stretch", "twin-image-fill", "twin-image-fit",
        "twin-stack-solid-grad", "twin-stack-grad-solid", "twin-blend-multiply", "twin-grad-opacity",
    ]

    /// MAE ceilings against Pen's render at 2x, set by the margin rule
    /// (max(measured×1.5, measured+0.25), `project/2026-09-26-mae-margin-rule.md`) and never
    /// looser than the bar they replaced.
    ///
    /// `icon-grad` measured 0.042 on 2026-09-27 (leaf VMKixs, same command) once icon glyphs
    /// were placed by the font's metrics, as Pen places them; its 1.66 was glyph placement.
    ///
    /// Measured 2026-09-27 (leaf HVBKsf, `swift test -j 3 --filter PenTextPaintTests`), with lines
    /// placed as Pen places them and Inter at its default optical size: 0.008, 0.029, 0.074,
    /// 0.085, 0.051 and 1.659 — the glyph mismatch below was optical size and line placement,
    /// and `icon-grad` (an icon font, which neither touched) keeps its bar.
    ///
    /// Measured 2026-09-26 with Inter registered (`TestFontRegistration`) and text set at
    /// Pen's rounded natural line height: 0.692, 3.591, 3.318, 6.575, 3.644 and 1.659. Before
    /// Inter was registered the boards drew in a fallback face and scored 1.52, 5.91, 4.82,
    /// 9.59, 4.89 and 1.66 under ceilings of "measured + 0.3"; `twin-image-stretch` and
    /// `icon-grad` keep those, which the formula would loosen. Before text paints landed,
    /// the glyphs were drawn black and these boards scored 2.67, 8.80, 7.21, 14.37, 6.86 and
    /// 5.40. What is left is the glyph mismatch, not the paint.
    private static let maeCeilings: [(String, Double)] = [
        ("txt-lin-h-fixed-left", 0.26), ("txt-lin-v-multiline", 0.28), ("twin-lin-h", 0.33),
        ("twin-radial", 0.34), ("twin-image-stretch", 0.31), ("icon-grad", 0.30),
        // Turned 20° about its anchor (F4, leaf nAuBKh): measured 0.017; 7.33 while the layout
        // pinned the turned box's corner at the anchor and the renderer pivoted at the box's centre.
        ("txt-rotated", 0.27),
    ]

    @Test("A ramp seen through a text node's glyphs has its stops on the node box's edges", arguments: ramps)
    func rampSpansTheNodeBox(artboard: String, axis: Axis) throws {
        let board = try Self.render(artboard)
        let (start, end) = axis == .x ? (board.box.minX, board.box.maxX) : (board.box.minY, board.box.maxY)
        let residual = try #require(DomainResidual(board.image, axis: axis, scale: Self.scale, from: start, to: end))
        #expect(residual.worst < 0.5, "\(artboard): a 10 pt band sits \(residual.worst) pt off the box's ramp")
        guard !Self.shortSpans.contains(artboard) else { return }
        let fit = try #require(PenFillDomainTests.RampFit(board.image, axis: axis, scale: Self.scale))
        #expect(abs(fit.stop0 - start) < 0.5, "\(artboard): stop 0 at \(fit.stop0), box edge \(start)")
        #expect(abs(fit.stop1 - end) < 0.5, "\(artboard): stop 1 at \(fit.stop1), box edge \(end)")
    }

    @Test("Every line of a ragged paragraph shares one ramp across the box, not one per line")
    func raggedLinesShareOneRamp() throws {
        let board = try Self.render("txt-lin-h-ragged")
        // Three lines of 72 pt at line height 1.2: 86.4 pt bands from the box's top.
        for line in 0 ..< 3 {
            let top = board.box.minY + 86.4 * Double(line)
            let band = CGRect(x: 0, y: top * 2, width: Double(board.image.width), height: 86.4 * 2).integral
            let cropped = try #require(board.image.cropping(to: band))
            let residual = try #require(DomainResidual(
                cropped, axis: .x, scale: Self.scale, from: board.box.minX, to: board.box.maxX
            ))
            #expect(residual.worst < 0.5, "line \(line): a 10 pt band sits \(residual.worst) pt off the box's ramp")
        }
    }

    @Test("A twin's text shows the colour its rectangle shows at the same place in the box", arguments: twins)
    func textMatchesItsRectangleTwin(artboard: String) throws {
        let interior = try Self.glyphInterior()
        let pixels = try #require(PenFillDomainTests.RGBA(Self.render(artboard).image))
        let offset = 140 * Self.scale
        var worst = 0
        for (px, py) in interior {
            let text = pixels.pixel(px, py)
            let rect = pixels.pixel(px, py + offset)
            let delta = max(abs(Int(text.r) - Int(rect.r)), abs(Int(text.g) - Int(rect.g)), abs(Int(text.b) - Int(rect.b)))
            worst = max(worst, delta)
        }
        #expect(worst <= 3, "\(artboard): worst channel difference \(worst) over \(interior.count) glyph pixels")
    }

    @Test("A gradient text board stays within its MAE ceiling against Pen", arguments: maeCeilings)
    func matchesPenWithinCeiling(artboard: String, ceiling: Double) throws {
        let rendered = try Self.render(artboard).image
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Text fill \(artboard) MAE: \(mae)")
        #expect(mae < ceiling, "\(artboard): MAE \(mae)")
    }

    // MARK: - Helpers

    enum BoardError: Error { case notAFrame(String) }

    /// How far a red→blue ramp's covered pixels sit from where a ramp over `start…end` puts them.
    ///
    /// Each fully covered pixel's `t = B / 255` implies a position `start + t · (end − start)`.
    /// Averaged over 10 pt bands along the axis, the implied position minus the actual one is
    /// that band's offset; `worst` is the largest, in points. Unlike an end-stop fit it does
    /// not extrapolate, so a short run of glyphs pins the domain as well as a long one.
    struct DomainResidual {
        let worst: Double

        init?(_ image: CGImage, axis: Axis, scale: Int, from start: Double, to end: Double) {
            guard let pixels = PenFillDomainTests.RGBA(image) else { return nil }
            var sums: [Int: (Double, Int)] = [:]
            for py in 0 ..< pixels.height {
                for px in 0 ..< pixels.width {
                    let p = pixels.pixel(px, py)
                    guard p.a == 255, p.g <= 3, abs(Int(p.r) + Int(p.b) - 255) <= 3 else { continue }
                    let t = Double(p.b) / 255
                    guard t > 0.02, t < 0.98 else { continue }
                    let position = (Double(axis == .x ? px : py) + 0.5) / Double(scale)
                    let band = Int((position / 10).rounded(.down))
                    let (sum, count) = sums[band] ?? (0, 0)
                    sums[band] = (sum + start + t * (end - start) - position, count + 1)
                }
            }
            let offsets = sums.values.filter { $0.1 >= 50 }.map { abs($0.0 / Double($0.1)) }
            guard let worst = offsets.max() else { return nil }
            self.worst = worst
        }
    }

    /// A rendered board and its text (or icon) node's box, in the board's points.
    struct Board {
        let image: CGImage
        let box: CGRect
    }

    static func render(_ artboard: String) throws -> Board {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        let node = try #require(document.children.first { $0.common.name == artboard })
        let rects = PenLayoutEngine.layout(document)
        let rect = try #require(rects[node.id])
        guard case let .frame(frame) = node.kind else { throw BoardError.notAFrame(artboard) }
        let child = try #require(frame.children?.first)
        let box = try #require(rects[child.id])
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: CGFloat(scale), rootNodeID: node.id,
            imageProvider: PenRenderer.fileImageProvider(relativeTo: fixturesDir)
        ))
        return Board(image: image, box: box.cgRect)
    }

    /// Pixels well inside the twins' glyphs: every twin sets the same "MMMM" in the same box,
    /// so the red→blue twin (never black inside a glyph) marks them for all of them. Eroded
    /// by two pixels so that no edge pixel, whose coverage differs by paint, is compared.
    static func glyphInterior() throws -> [(Int, Int)] {
        let pixels = try #require(PenFillDomainTests.RGBA(render("twin-lin-h").image))
        let top = 40 * scale, bottom = 160 * scale
        func inked(_ px: Int, _ py: Int) -> Bool {
            let p = pixels.pixel(px, py)
            return p.a == 255 && Int(p.r) + Int(p.b) >= 250 && p.g <= 3
        }
        var interior: [(Int, Int)] = []
        for py in top ..< bottom {
            for px in 2 ..< pixels.width - 2 {
                let covered = (-2 ... 2).allSatisfy { dy in (-2 ... 2).allSatisfy { dx in inked(px + dx, py + dy) } }
                if covered { interior.append((px, py)) }
            }
        }
        try #require(interior.count > 5000, "only \(interior.count) interior glyph pixels")
        return interior
    }
}
