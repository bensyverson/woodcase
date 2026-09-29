//
//  PenInnerShadowShapesSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the Core Graphics renderer's inner shadows on SVG-like shapes and icons, and its
/// painted strokes on flat lines, against Pen's own 2x exports (leaf 4fZZ38).
///
/// `render-inner-shadow-shapes.pen` and `render-painted-lines.pen` are written by
/// `scripts/gen-react-fx-fixtures`; their references come from
/// `scripts/pen-oracle <fixture> --scale 2`.
struct PenInnerShadowShapesSnapshotTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Each board with its MAE ceiling against Pen's 2x export, by the margin rule
    /// (max(measured × 1.5, measured + 0.25), rounded up; `project/2026-09-26-mae-margin-rule.md`),
    /// measured 2026-09-28 with `swift test -j 3 --filter PenInnerShadowShapesSnapshotTests`.
    /// `render-painted-lines-fill-degenerate` is left out: a kept divergence
    /// (<doc:PenInteroperability>, *Kept Divergences*), pinned by ``degenerateRampsKeepTheirBand()``.
    static let boards: [(fixture: String, board: String, ceiling: Double)] = [
        ("render-inner-shadow-shapes", "polygon", 0.47), // measured 0.218
        ("render-inner-shadow-shapes", "path-stroked", 0.31), // measured 0.056
        ("render-inner-shadow-shapes", "path-viewbox", 0.52), // measured 0.261
        ("render-inner-shadow-shapes", "donut", 0.65), // measured 0.393; was 19.971, its hole filled black
        ("render-inner-shadow-shapes", "arc", 0.48), // measured 0.229
        ("render-inner-shadow-shapes", "blended", 0.52), // measured 0.263
        ("render-inner-shadow-shapes", "two-shadows", 0.50), // measured 0.249
        ("render-inner-shadow-shapes", "gradient-fill", 0.49), // measured 0.240
        ("render-inner-shadow-shapes", "icon-lucide", 0.99), // measured 0.655; was 3.913, no inner shadow on an icon
        ("render-inner-shadow-shapes", "icon-material", 0.71), // measured 0.470; was 2.613
        ("render-inner-shadow-shapes", "icon-both", 0.66), // measured 0.408; was 1.365
        ("render-painted-lines", "fill-gradients", 0.27), // measured 0.019; was 3.781, a paint over a zero-height box drew nothing
        ("render-painted-lines", "fill-stack", 0.26), // measured 0.009; was 2.139
        ("render-painted-lines", "fixed", 0.27), // measured 0.011; was 1.753
    ]

    @Test("The case list names every board but the kept divergence")
    func caseListIsComplete() throws {
        for fixture in Set(Self.boards.map(\.fixture)) {
            let names = try PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: Self.fixturesDir)
            let listed = Self.boards.filter { $0.fixture == fixture }.map(\.board)
            #expect(names.filter { $0 != "fill-degenerate" } == listed, "\(fixture)")
        }
    }

    @Test("The Core Graphics renderer draws each board within its ceiling of Pen's export", arguments: boards)
    func rendersLikePen(fixture: String, board: String, ceiling: Double) throws {
        TestFontRegistration.registerTestFonts()
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(fixture)-\(board)", fixturesDir: Self.fixturesDir
        ))
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: board, in: fixture, fixturesDir: Self.fixturesDir, scale: 2
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("CG \(fixture)-\(board) MAE: \(mae)")
        #expect(mae < ceiling, "\(fixture)-\(board): MAE \(mae)")
    }

    /// Pen lays a flat line's stroke paint over its zero-height box and collapses a ramp
    /// across the line — a slanted one to its two end colors split at the line, a vertical
    /// or radial one to black; the renderer paints the ramp over the stroke's band, a kept
    /// divergence (<doc:PenInteroperability>, *Kept Divergences*). The board is pinned at its
    /// measured MAE + 0.5 so the choice cannot drift unseen: 7.974 before the band, when the
    /// renderer drew these lines not at all.
    @Test("A ramp across a flat line keeps its band, where Pen collapses it")
    func degenerateRampsKeepTheirBand() throws {
        let fixture = "render-painted-lines"
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(fixture)-fill-degenerate", fixturesDir: Self.fixturesDir
        ))
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: "fill-degenerate", in: fixture, fixturesDir: Self.fixturesDir, scale: 2
        ))
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("CG \(fixture)-fill-degenerate MAE: \(mae)")
        #expect(abs(mae - Self.degenerateMAE) < 0.5, "MAE \(mae), pinned at \(Self.degenerateMAE)")
    }

    /// The measured MAE of `render-painted-lines-fill-degenerate`, the kept divergence.
    static let degenerateMAE = 16.297
}
