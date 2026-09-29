//
//  PenMeshFillSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the renderer's mesh gradient fills against Pen's own exports.
///
/// `render-mesh-gradients.pen` is the report's probe fixture
/// (`project/2026-09-26-mesh-gradients.md`, Appendix A): eight artboards covering a 2×2, a
/// 3×3, a warped 3×3, a translucent mesh at `opacity 0.7` inside an ellipse, curved
/// handles, black to white, an irregular 4×3 and a folded 2×2. The references are Pen's
/// PNG exports at 1x and 2x:
///
/// ```
/// scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-mesh-gradients.pen --out <dir> --scale 1,2
/// ```
///
/// (`pen` CLI 0.3.9, sandbox off), copied into `Fixtures/` as
/// `render-mesh-gradients-<artboard>@<n>x.png`.
///
/// Woodcase does not reproduce Pen's pixels exactly, on purpose: Pen cuts every patch
/// into a fixed 32 × 32 cells, and Woodcase subdivides adaptively to a quarter pixel and
/// half a color step (<doc:PenMeshGradients>, the ruling on leaf `OHdROl`), and it rounds
/// colors where Pen truncates. So each artboard's MAE is pinned at what it measures, plus
/// a small margin, and a rise past the pin is a regression. ``expectedMAE`` says why each
/// value is what it is.
struct PenMeshFillSnapshotTests {
    private static let fixture = "render-mesh-gradients"
    static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard, in document order.
    private static let artboards = ["m2x2", "m3x3", "mwarp", "malpha", "mcurve", "mbw", "m4x3", "mfold"]

    /// The scales Pen exported.
    private static let scales = [1, 2]

    /// The MAE each artboard measured against Pen at 1x and 2x, plus ``margin``.
    ///
    /// Measured 2026-09-26 with `swift test --filter PenMeshFillSnapshotTests` (the values
    /// it prints; `pen` CLI 0.3.9 references). Almost all of it is one rule, not the
    /// tessellation: the mesh core rounds each color to the nearest 8-bit step where Pen
    /// truncates (<doc:PenMeshGradients>, "No seams"), so about half of all color samples
    /// read one step brighter than Pen's and almost none darker. That is a signed error of +0.5 on
    /// each of red, green and blue and none on alpha, so an MAE of 3 × 0.5 / 4 ≈ 0.37 on
    /// every opaque board, at either scale. Differences of two steps or more are a few
    /// dozen pixels per board.
    ///
    /// - `m2x2`, `m3x3`, `mwarp`, `mcurve`, `mbw`, `m4x3`: opaque, the rounding bias alone
    ///   (0.362–0.380).
    /// - `malpha`: lower (0.25 at 1x, 0.23 at 2x). Its mesh is translucent, composited at
    ///   `opacity 0.7` over white, and there the one-step differences run both ways (a
    ///   signed −0.1 to −0.2 per channel) instead of all brightening; a few hundred pixels
    ///   on the ellipse's anti-aliased edge differ by up to 27 steps, where CoreGraphics'
    ///   and Skia's edge coverage disagree.
    /// - `mfold`: the rounding bias, less over the area the fold leaves transparent in both
    ///   renders, plus a few dozen pixels on the fold's edges, which neither
    ///   renderer anti-aliases, that differ by up to 252 steps where the two rasterizers
    ///   disagree about which patch covers a pixel center (0.33 at 1x, 0.37 at 2x).
    private static let expectedMAE: [String: [Int: Double]] = [
        "m2x2": [1: 0.3784, 2: 0.3775],
        "m3x3": [1: 0.3686, 2: 0.3696],
        "mwarp": [1: 0.3621, 2: 0.3641],
        "malpha": [1: 0.2468, 2: 0.2349],
        "mcurve": [1: 0.3757, 2: 0.3757],
        "mbw": [1: 0.3662, 2: 0.3662],
        "m4x3": [1: 0.3793, 2: 0.3803],
        "mfold": [1: 0.3279, 2: 0.3698],
    ].mapValues { $0.mapValues { $0 + margin } }

    /// Room above each measurement for float noise across machines and toolchains.
    private static let margin = 0.02

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
        #expect(Set(Self.expectedMAE.keys) == Set(Self.artboards))
    }

    @Test("Each mesh matches Pen's export within its pinned MAE", arguments: artboards, scales)
    func matchesPen(artboard: String, scale: Int) async throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        let limit = try #require(Self.expectedMAE[artboard]?[scale])
        print("Mesh \(artboard) @\(scale)x MAE: \(String(format: "%.4f", mae))")
        await MAEReport.shared.record(id: "mesh-\(artboard)@\(scale)x", mae: mae, limit: limit)
        #expect(mae <= limit, "\(artboard) @\(scale)x: MAE \(mae), pinned at \(limit)")
    }

    @Test("Each corner vertex's color lands in its corner of the box", arguments: scales)
    func cornerColorsLandAtCorners(scale: Int) throws {
        let image = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: "m2x2", in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let pixels = try #require(PenFillDomainTests.RGBA(image))
        let last = 200 * scale - 1
        // Color eases with smoothstep, so a pixel center half a pixel in from a corner is
        // within a fraction of a level of that corner's vertex color.
        let corners: [(Int, Int, PenFillDomainTests.RGBA.Pixel)] = [
            (0, 0, .init(r: 255, g: 0, b: 0, a: 255)),
            (last, 0, .init(r: 0, g: 255, b: 0, a: 255)),
            (0, last, .init(r: 0, g: 0, b: 255, a: 255)),
            (last, last, .init(r: 255, g: 255, b: 0, a: 255)),
        ]
        for (x, y, expected) in corners {
            let actual = pixels.pixel(x, y)
            let error = max(
                abs(Int(actual.r) - Int(expected.r)), abs(Int(actual.g) - Int(expected.g)),
                abs(Int(actual.b) - Int(expected.b)), abs(Int(actual.a) - Int(expected.a))
            )
            #expect(error <= 1, "(\(x), \(y)) @\(scale)x: \(actual), expected \(expected)")
        }
    }
}
