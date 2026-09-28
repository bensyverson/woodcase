//
//  SlotOverrideKeysSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins which `descendants` keys reach a node written into a nested instance's slot,
/// against Pen's own exports.
///
/// `slot-override-keys.pen` holds one artboard per key form: an instance whose component
/// fills a nested instance's slot, carrying one override (or two that name the same
/// node). Injected nodes are red; an override that applies paints blue (a bare key) or
/// green (a path). The references are Pen's PNG exports:
///
/// ```
/// scripts/pen-oracle Tests/WoodcaseTests/Fixtures/slot-override-keys.pen --scale 1 --accept-invalid --no-layout
/// ```
///
/// (`pen` CLI 0.3.9, sandbox off; the component exports are deleted, and Pen cannot
/// settle the layout of `bare-ref-children`, hence `--no-layout`). The rule they
/// establish is in `project/2026-09-26-slot-override-keys.md`.
struct SlotOverrideKeysSnapshotTests {
    static let fixture = "slot-override-keys"
    static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order.
    static let artboards = [
        "bare-injected", "path-injected", "bare-and-path", "bare-and-path-no-merge",
        "bare-nested-plain", "bare-injected-deep", "bare-injected-ref", "bare-injected-twice",
        "bare-injected-replace", "path-injected-twice", "path-skips-injected-ref",
        "path-from-injected-ref", "path-injected-deep", "path-through-injected-frame",
        "path-ref-injected-frame", "path-ref-then-slot", "path-slot-first", "path-plain-frame",
        "outer-bare", "outer-short-path", "outer-full-path", "bare-ref-children",
    ]

    /// The pin: every artboard is axis-aligned solid rectangles on whole points, so the
    /// only disagreement left is the one ellipse's antialiased edge.
    /// max(measured×1.5, measured+0.25) over the worst case (`bare-injected-replace`, 0.077).
    private static let limit = 0.33

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(Array(names.prefix(Self.artboards.count)) == Self.artboards)
    }

    @Test("Each override key draws what Pen draws", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: 1
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Slot override key \(artboard) MAE: \(String(format: "%.4f", mae))")
        #expect(mae <= Self.limit, "\(artboard): MAE \(mae), pinned at \(Self.limit)")
    }
}
