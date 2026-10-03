//
//  PenImageCropSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Woodcase

/// Pins how the Core Graphics renderer places an image paint by its `mode` and crops it by
/// its `transform` (format 2.20) against Pen 1.2.15's own exports.
///
/// `render-image-crops.pen` (written by `scripts/gen-image-crop-fixture`) has one black,
/// clipped artboard per case: stretch, cover and contain on a wide (200×120) and a tall
/// (100×160) rectangle, each with no crop and six crops; a missing mode; a crop on an
/// ellipse, on an outer stroke and at half opacity. The image is the UV map
/// (`images/uv-map.png`, red = u, green = v). The references are Pen's 2x PNG exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-image-crops.pen --scale 2`).
struct PenImageCropSnapshotTests {
    private static let fixture = "render-image-crops"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale = 2

    /// Every artboard, in document order.
    private static let artboards: [String] = {
        let crops = ["none", "right-half", "zoom-center", "shifted-past-edge", "larger-than-image", "sheared", "quarter-turn"]
        let grid = ["stretch", "cover", "contain"].flatMap { mode in
            ["wide", "tall"].flatMap { box in crops.map { "\(mode)-\(box)-\($0)" } }
        }
        return grid + [
            "missing-wide-none", "missing-wide-zoom-center", "contain-ellipse-zoom", "cover-ellipse-shifted",
            "cover-stroke-zoom", "contain-opacity-right-half",
        ]
    }()

    /// The MAE every board stays under: max(measured×1.5, measured+0.25) over the worst case
    /// (`contain-wide-sheared`, 0.076; `swift test --filter PenImageCropSnapshotTests`,
    /// 2026-10-03). Before the renderer read crops, the cropped boards scored 1.9–23.8.
    private static let limit = 0.33

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each image placement and crop matches Pen's render", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale),
            imageProvider: PenRenderer.fileImageProvider(relativeTo: Self.fixturesDir)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Image crop \(artboard) MAE: \(String(format: "%.3f", mae))")
        #expect(mae < Self.limit, "\(artboard): MAE \(mae)")
    }
}
