//
//  PenPaintedExtentProbeTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Holds ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)`` to Pen's own exports,
/// which Pen frames on a node's painted extent.
///
/// `geometry-probe.pen` is written by `scripts/gen-geometry-probe`; the PNGs beside it are
/// Pen's 2x exports of its boards (`scripts/pen-oracle <fixture> --out <dir> --scale 2`,
/// leaf `w2er6i`, `project/2026-09-28-geometry-model.md` § 5). Every stroke is 12 pt; the
/// shadow is offset (10, 10) with blur 8.
struct PenPaintedExtentProbeTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Pen's exports are at 2x.
    private static let scale: CGFloat = 2

    /// Each exported board and the pixel size of Pen's export of it.
    private static let exports: [(board: String, width: Int, height: Int)] = [
        ("x1", 296, 216), ("x2", 299, 270), ("x3", 260, 180), ("x4", 224, 144),
        ("free", 1488, 803), ("groups", 1440, 733),
    ]

    @Test("Grown to whole pixels at 2x, the painted extent is the size of Pen's export", arguments: exports)
    func exportSize(board: String, width: Int, height: Int) throws {
        let (document, rects) = try Self.probe()
        let node = try #require(document.children.first { $0.id == board })
        let extent = try PenLayoutEngine.paintedExtent(of: node, rect: #require(rects[node.id]), layoutRects: rects)
        let grown = extent.grownToWholePixels(at: Double(Self.scale))
        #expect(Int((grown.width * Self.scale).rounded()) == width, "\(board): \(extent)")
        #expect(Int((grown.height * Self.scale).rounded()) == height, "\(board): \(extent)")
    }

    /// The painted extents the finding derived from Pen's exports, exactly: x1's outer
    /// band (−12…112) and its shadow's copy (+10, ±12); x2's 124×84 band turned 30°; x3's
    /// blur inflating 15; x4's centered band inflating 6.
    @Test("The top-level probes' painted extents are the ones Pen's exports imply")
    func topLevelSizes() throws {
        let (document, rects) = try Self.probe()
        let s30 = 0.5, c30 = cos(Double.pi / 6)
        let want: [String: (Double, Double, Double, Double)] = [
            "x1": (2100 - 14, 900 - 14, 148, 108),
            "x2": (2400 - 12 * c30 - 12 * s30, 900 - 112 * s30 - 12 * c30, 124 * c30 + 84 * s30, 124 * s30 + 84 * c30),
            "x3": (2700 - 15, 900 - 15, 130, 90),
            "x4": (3000 - 6, 900 - 6, 112, 72),
        ]
        for (id, (x, y, width, height)) in want.sorted(by: { $0.key < $1.key }) {
            let node = try #require(document.children.first { $0.id == id })
            let got = try PenLayoutEngine.paintedExtent(of: node, rect: #require(rects[id]), layoutRects: rects)
            #expect(
                abs(got.x - x) < 1e-9 && abs(got.y - y) < 1e-9
                    && abs(got.width - width) < 1e-9 && abs(got.height - height) < 1e-9,
                "\(id): \(got)"
            )
        }
    }

    /// The `free` board is 720×360 at (1200, 500); r6's flipped per-side band reaches 24 pt
    /// left of it and r5's mitered band, turned 30° and flipped, 41.03 pt above it.
    @Test("An unclipped board's painted extent reaches its children's bands")
    func freeBoard() throws {
        let (document, rects) = try Self.probe()
        let node = try #require(document.children.first { $0.id == "free" })
        let got = try PenLayoutEngine.paintedExtent(of: node, rect: #require(rects["free"]), layoutRects: rects)
        let top = 40 - (72 * 0.5 + 52 * cos(Double.pi / 6))
        #expect(abs(got.x - 1176) < 1e-9 && abs(got.width - 744) < 1e-9, "\(got)")
        #expect(abs(got.y - (500 + top)) < 1e-9 && abs(got.height - (360 - top)) < 1e-9, "\(got)")
    }

    /// MAE ceilings for the renders framed on the painted extent, set by the margin rule
    /// (max(measured×1.5, measured+0.25), `project/2026-09-26-mae-margin-rule.md`).
    ///
    /// Measured 2026-09-28 (leaf Wkr2Pd, `swift test -j 3 --filter PenPaintedExtentProbeTests`):
    /// `x1` 0.045, `x2` 0.035, `x3` 0.486 (the layer blur), `x4` 0.000, `free` 0.229,
    /// `groups` 0.045. Framed instead on the extent snapped outward to whole pixels —
    /// the first guess at Pen's framing — `x2` scored 0.348, `free` 1.073 and `groups`
    /// 0.270: Pen keeps the extent's fractional corner and rounds only the pixel size up.
    private static let maeCeilings: [(board: String, ceiling: Double)] = [
        ("x1", 0.30), ("x2", 0.29), ("x3", 0.74), ("x4", 0.25), ("free", 0.48), ("groups", 0.30),
    ]

    @Test("Framed on its painted extent, each board lines up with Pen's export", arguments: maeCeilings)
    func rendersLikePen(board: String, ceiling: Double) throws {
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "geometry-probe-\(board)", fixturesDir: Self.fixturesDir
        ))
        let rendered = try #require(try PenSnapshotTestHelpers.renderPaintedArtboard(
            named: board, in: "geometry-probe", fixturesDir: Self.fixturesDir, scale: Self.scale
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Painted extent \(board) MAE: \(mae)")
        #expect(mae < ceiling, "\(board): MAE \(mae)")
    }

    /// x5-x7 are text: Pen's `computeVisualLocalBounds` for a text node returns its Skia
    /// fill path's tight bounds — the glyph ink, not the box
    /// (`project/2026-09-28-geometry-model.md`, "Pen's own code" for the text class). x5's
    /// unbreakable word is wider and taller than its fixed box; x6 is italic, whose slant
    /// reaches past the upright box; x7 is an ordinary paragraph that wraps past its fixed
    /// height. All three overflow their declared box on at least one side, and Woodcase's
    /// own text measurement (``Woodcase/PenLayoutEngine/textInkBounds(of:box:)``) now
    /// grows to follow them there instead of stopping at the box.
    ///
    /// Not held to the same whole-pixel exactness as x1–x4: Core Text and Pen's Skia
    /// disagree on Inter's exact glyph metrics at these sizes even with optical sizing
    /// off (``Woodcase/PenTextMeasurer/opticalSizingOff``, `PenTextOpticalSizeTests`: "3 pt
    /// narrower … for two letters at 32 pt, 9 pt for a 56 pt word") — a font-rendering-engine
    /// gap this fix does not close, not a geometry bug. Measured 2026-09-28
    /// (`swift test -j 3 --filter PenPaintedExtentProbeTests`): x5 off by (5, 4) px, x6 by
    /// (8, 4), x7 by (15, 2), with image or outline bounds alike; each board is held to its
    /// own gap plus 2 px. The box
    /// this replaced missed by (19, 131), (58, 3) and (87, 57) — the fix is not a rounding
    /// nicety, it changes which shape is even being measured.
    private static let textOverflowExports: [(board: String, width: Int, height: Int, tolerance: Int)] = [
        ("x5", 101, 171, 7), ("x6", 122, 77, 10), ("x7", 153, 117, 17),
    ]

    @Test(
        "A text's painted extent grows toward Pen's export, within the Core Text/Skia glyph gap",
        arguments: textOverflowExports
    )
    func textExtentApproachesPensExport(board: String, width: Int, height: Int, tolerance: Int) throws {
        let (document, rects) = try Self.probe()
        let node = try #require(document.children.first { $0.id == board })
        let extent = try PenLayoutEngine.paintedExtent(of: node, rect: #require(rects[node.id]), layoutRects: rects)
        let grown = extent.grownToWholePixels(at: Double(Self.scale))
        let gotWidth = Int((grown.width * Self.scale).rounded())
        let gotHeight = Int((grown.height * Self.scale).rounded())
        #expect(abs(gotWidth - width) <= tolerance, "\(board): got \(gotWidth), Pen \(width): \(extent)")
        #expect(abs(gotHeight - height) <= tolerance, "\(board): got \(gotHeight), Pen \(height): \(extent)")
    }

    /// x8-x9 are icons: Pen's `computeVisualLocalBounds` for its icon class (`DJt`)
    /// returns `fillPath.bounds` — the vector glyph, fitted to the box by its *shorter*
    /// side and centered, then measured tightly — not the box
    /// (`project/2026-09-28-geometry-model.md`, "Pen's own code" for the icon class).
    /// x8's box (60×20) is far wider than its glyph fits; x9 is a "minus", a bar far
    /// flatter than its 40×40 box. ``Woodcase/PenLayoutEngine/iconInkBounds(of:box:)``
    /// measures the outline of the glyph ``Woodcase/PenIconGlyph`` places for drawing;
    /// the slack is the vendor font against Pen's own vector icon, a few pixels.
    private static let iconOverflowExports: [(board: String, width: Int, height: Int, tolerance: Int)] = [
        ("x8", 37, 36, 4), ("x9", 54, 7, 4),
    ]

    @Test(
        "An icon's painted extent is its fitted glyph ink, close to Pen's export",
        arguments: iconOverflowExports
    )
    func iconExtentApproachesPensExport(board: String, width: Int, height: Int, tolerance: Int) throws {
        let (document, rects) = try Self.probe()
        let node = try #require(document.children.first { $0.id == board })
        let extent = try PenLayoutEngine.paintedExtent(of: node, rect: #require(rects[node.id]), layoutRects: rects)
        let grown = extent.grownToWholePixels(at: Double(Self.scale))
        let gotWidth = Int((grown.width * Self.scale).rounded())
        let gotHeight = Int((grown.height * Self.scale).rounded())
        #expect(abs(gotWidth - width) <= tolerance, "\(board): got \(gotWidth), Pen \(width): \(extent)")
        #expect(abs(gotHeight - height) <= tolerance, "\(board): got \(gotHeight), Pen \(height): \(extent)")
    }

    // MARK: - Helpers

    /// The probe, resolved and laid out as the renderer reads it.
    private static func probe() throws -> (PenDocument, [String: PenRect]) {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("geometry-probe.pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        return (document, PenLayoutEngine.layout(document))
    }
}
