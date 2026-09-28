//
//  PenTransformedFreeTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins where a turned or flipped node that its parent does not lay out lands: Pen turns and
/// flips it about its `x`/`y` anchor, and its layout rect is the bounds of the result.
///
/// Both fixtures are Pen-oracle references (`scripts/pen-oracle <fixture> --scale 2`), so the
/// rects are Pen's own settled layout and the PNGs its own exports:
///
/// - `render-rotated-free.pen`: a rectangle, fixed-width text and auto text, each at
///   `x: 80, y: 60, rotation: -20` in a `layout: none` frame, and an unturned control.
/// - `render-transformed-free.pen`: a turned root rectangle and root frame, an absolute
///   child of a flex frame beside a turned flex child, a turned child of a group, a turned
///   frame inside a `layout: none` frame, and three flipped nodes, two of them turned too.
///
/// See `project/2026-09-27-fidelity-gaps.md`, F4.
struct PenTransformedFreeTests {
    /// Both text boards set Inter; without it they measure the fallback face.
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Pen's exports are at 2x.
    private static let scale: CGFloat = 2

    /// How far a rect may sit from Pen's, in points.
    private static let tolerance = 0.5

    @Test("Layout matches Pen's settled layout", arguments: ["render-rotated-free", "render-transformed-free"])
    func layoutMatchesPen(fixture: String) throws {
        let document = try Self.document(fixture)
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixturesDir.appendingPathComponent("\(fixture).layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        for (id, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = try #require(actual[id], "\(fixture): no rect for \(id)")
            let off = max(abs(got.x - want.x), abs(got.y - want.y), abs(got.width - want.width), abs(got.height - want.height))
            #expect(off < Self.tolerance, "\(fixture) \(id): got \(got), Pen \(want)")
        }
    }

    /// MAE ceilings against Pen's 2x exports, set by the margin rule (max(measured×1.5,
    /// measured+0.25), `project/2026-09-26-mae-margin-rule.md`).
    ///
    /// Measured 2026-09-27 (leaf nAuBKh, `swift test -j 3 --filter PenTransformedFreeTests`):
    /// `rrect` 0.007, `rtxtf` and `rtxta` 0.144, `rtxts` 0.140, `rootrect` 0.064, `rootframe`
    /// 0.030, `flexabs` 0.009, `grouped` 0.003, `nested` 0.005, `flips` 0.046. Before, with the
    /// turned box's corner pinned at the anchor and auto-sized text drawn into its turned
    /// bounds: 2.57, 4.98, 4.98, 0.14, 34.0, 41.4, 5.10, 3.40, 8.20 and 14.08.
    private static let maeCeilings: [(fixture: String, board: String, ceiling: Double)] = [
        ("render-rotated-free", "rrect", 0.26),
        ("render-rotated-free", "rtxtf", 0.39),
        ("render-rotated-free", "rtxta", 0.39),
        ("render-rotated-free", "rtxts", 0.39),
        ("render-transformed-free", "rootrect", 0.31),
        ("render-transformed-free", "rootframe", 0.28),
        ("render-transformed-free", "flexabs", 0.26),
        ("render-transformed-free", "grouped", 0.25),
        ("render-transformed-free", "nested", 0.25),
        ("render-transformed-free", "flips", 0.30),
    ]

    @Test("The Core Graphics renderer draws each board within its ceiling of Pen's export", arguments: maeCeilings)
    func rendersLikePen(fixture: String, board: String, ceiling: Double) throws {
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(fixture)-\(board)", fixturesDir: Self.fixturesDir
        ))
        // A turned root's bounds are fractional (208.46 pt); Pen's export rounds them up to
        // whole pixels, so the board is drawn on a canvas of the export's size.
        let document = try Self.document(fixture)
        let node = try #require(document.children.first { $0.common.name == board })
        let rects = PenLayoutEngine.layout(document)
        let rendered = try #require(PenRenderer.render(
            document, layoutRects: rects,
            size: CGSize(width: CGFloat(reference.width) / Self.scale, height: CGFloat(reference.height) / Self.scale),
            scale: Self.scale, rootNodeID: node.id
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Transformed free \(fixture)-\(board) MAE: \(mae)")
        #expect(mae < ceiling, "\(fixture)-\(board): MAE \(mae)")
    }

    /// A fixture, parsed and resolved as the renderer reads it.
    private static func document(_ fixture: String) throws -> PenDocument {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        return try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
    }
}
