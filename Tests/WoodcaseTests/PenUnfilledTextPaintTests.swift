import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins what a text or icon node draws when it has no enabled paint: nothing, as Pen does.
///
/// `render-text-unfilled.pen` puts an Inter 44 bold "Ink" and a lucide square on a #808080
/// board, both carrying the board's fill shape. The references are Pen's 2x exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-text-unfilled.pen --scale 2
/// --no-layout --accept-invalid`, pen CLI 0.3.9, 2026-09-27; `--accept-invalid` because
/// `bad-hex` is not a valid colour). What Pen drew:
///
/// - no `fill` key, `fill: []`, only a disabled colour, only a disabled gradient, and a fully
///   transparent colour: nothing — the export is the plain grey board;
/// - `#000000` (the control), an unparseable hex and an unresolved `$variable`: black, byte
///   for byte the same export — an *enabled* solid that fails to parse still paints black;
/// - a gradient, an image, and a disabled colour under an enabled one: the enabled paint.
///
/// A shader fill draws its shader in Pen; the Core Graphics renderer does not execute
/// shaders, so that shape is not a board here.
struct PenUnfilledTextPaintTests {
    /// Every board sets Inter; without it the glyphs measure a fallback face.
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixture = "render-text-unfilled"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale = 2

    /// The board's own fill, which is all an unfilled board may show.
    private static let grey = PenFillDomainTests.RGBA.Pixel(r: 128, g: 128, b: 128, a: 255)

    /// Boards whose text and icon have no enabled paint.
    private static let unfilled = ["no-fill", "empty-list", "disabled", "disabled-gradient", "transparent"]

    /// Boards whose one enabled solid does not parse: Pen paints those black.
    private static let unparsed = ["bad-hex", "missing-variable"]

    /// MAE ceilings against Pen's render at 2x, set by the margin rule
    /// (max(measured×1.5, measured+0.25), `project/2026-09-26-mae-margin-rule.md`).
    ///
    /// Measured 2026-09-27 (leaf PRFPX5, `swift test -j 3 --filter PenUnfilledTextPaintTests`):
    /// 0.000 on every unfilled board (8.947 before the fix, when the glyphs drew black);
    /// 0.681 on `control`, `bad-hex` and `missing-variable`; 0.677 on `disabled-then-solid`;
    /// 0.053 on `gradient`; 0.040 on `image`. The solids' 0.68 is Core Text's glyph
    /// rasterisation against Pen's, the same on every black board.
    private static let maeCeilings: [(String, Double)] = [
        ("no-fill", 0.25), ("empty-list", 0.25), ("disabled", 0.25), ("disabled-gradient", 0.25),
        ("transparent", 0.25), ("control", 1.03), ("bad-hex", 1.03), ("missing-variable", 1.03),
        ("disabled-then-solid", 1.02), ("gradient", 0.31), ("image", 0.30),
    ]

    @Test("A text and icon with no enabled paint draw nothing", arguments: unfilled)
    func unfilledDrawsNothing(artboard: String) throws {
        let pixels = try #require(PenFillDomainTests.RGBA(Self.render(artboard)))
        var inked = 0
        for py in 0 ..< pixels.height {
            for px in 0 ..< pixels.width where pixels.pixel(px, py) != Self.grey {
                inked += 1
            }
        }
        #expect(inked == 0, "\(artboard): \(inked) pixels differ from the board's grey")
    }

    @Test("A text and icon whose one solid does not parse draw black, as Pen does", arguments: unparsed)
    func unparsedSolidDrawsBlack(artboard: String) throws {
        let rendered = try #require(PenFillDomainTests.RGBA(Self.render(artboard)))
        let control = try #require(PenFillDomainTests.RGBA(Self.render("control")))
        #expect(rendered.bytes == control.bytes, "\(artboard) does not draw as #000000 does")
    }

    @Test("Each board stays within its MAE ceiling against Pen", arguments: maeCeilings)
    func matchesPenWithinCeiling(artboard: String, ceiling: Double) throws {
        let rendered = try Self.render(artboard)
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Unfilled text \(artboard) MAE: \(mae)")
        #expect(mae < ceiling, "\(artboard): MAE \(mae)")
    }

    // MARK: - Helpers

    /// Renders one board of the fixture at the references' scale.
    static func render(_ artboard: String) throws -> CGImage {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        let node = try #require(document.children.first { $0.common.name == artboard })
        let rects = PenLayoutEngine.layout(document)
        let rect = try #require(rects[node.id])
        return try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: CGFloat(scale), rootNodeID: node.id,
            imageProvider: PenRenderer.fileImageProvider(relativeTo: fixturesDir)
        ))
    }
}
