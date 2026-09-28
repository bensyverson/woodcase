//
//  PenViewBoxSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Compares the Woodcase render of `viewbox-experiment.pen` against Pen.app's own
/// export of the same file, using mean absolute error (MAE).
///
/// Pen exported the `root` frame at scale 1. Pen frames an export on the node's painted
/// extent, not its layout rect, so the 900×300 frame becomes a 900×340 image whose origin
/// sits 40 px above the frame — the green triangle's `viewBox` overflow. The render is
/// framed on the same extent (``PenSnapshotTestHelpers/renderPaintedArtboard(named:in:fixturesDir:scale:imageProvider:)``),
/// so the two images align pixel for pixel without a hand-measured offset.
///
/// The file also carries three probe nodes at document level for later slices: a `line`,
/// a `script`, and a rectangle with a `shader` fill — none of the three is inside `root`,
/// so rendering only `root` is unaffected by them.
struct PenViewBoxSnapshotTests {
    private let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("v2.17")

    @Test("viewbox-experiment matches Pen's own export within threshold")
    func viewBoxExperiment() throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderPaintedArtboard(
            named: "viewbox-experiment", in: "viewbox-experiment", fixturesDir: fixturesDir, scale: 1
        ))
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "viewbox-experiment-pen", fixturesDir: fixturesDir)
        )
        #expect(rendered.width == reference.width)
        #expect(rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("viewbox-experiment MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.015.
        #expect(mae < 0.27)
    }
}
