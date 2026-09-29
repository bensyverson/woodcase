//
//  PenMeshColorSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the renderer's reading of mesh colors against Pen's own exports.
///
/// `render-mesh-colors.pen` holds one 40×40 frame per color string: a `#00FF00` fill
/// under a 2×2 mesh of that color at every vertex, so a color Pen reads as nothing
/// shows green. The references are Pen's PNG exports:
///
/// ```
/// scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-mesh-colors.pen --scale 1 --accept-invalid --no-layout
/// ```
///
/// (`pen` CLI 0.3.9, sandbox off, 2026-09-27). ``PenMeshColorTests`` holds the parse to
/// the same table row by row; `SwiftUIRenderTests` renders the fixture's boards too.
struct PenMeshColorSnapshotTests {
    private static let fixture = "render-mesh-colors"

    /// Every artboard, one color string each.
    private static let artboards = [
        "control", "badhex", "word", "rgba", "rgba-half", "five", "empty", "prefix", "minus", "space", "plus",
        "zerox", "short-bad", "short-minus", "trailing-hash", "double-hash", "hash-only", "no-hash", "lower",
        "seven", "nine", "mid-hash", "six-minus-one", "six-mid", "eight-prefix", "eight-tail", "eight-bad",
        "eight-minus", "eight-mid", "eight-space",
    ]

    /// The pin: every board measured 0.00 on 2026-09-27
    /// (`swift test --filter PenMeshColorSnapshotTests`); a flat color leaves nothing but
    /// 8-bit rounding to disagree about.
    private static let limit = 0.05

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(
            in: Self.fixture, fixturesDir: PenMeshMalformedPointSnapshotTests.fixturesDir
        )
        #expect(names == Self.artboards)
    }

    @Test("Each mesh color paints as Pen paints it", arguments: artboards)
    func matchesPen(artboard: String) async throws {
        let directory = PenMeshMalformedPointSnapshotTests.fixturesDir
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: directory, scale: 1
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: directory
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        await MAEReport.shared.record(id: "mesh-color-\(artboard)", mae: mae, limit: Self.limit)
        #expect(mae <= Self.limit, "\(artboard): MAE \(mae), pinned at \(Self.limit)")
    }
}
