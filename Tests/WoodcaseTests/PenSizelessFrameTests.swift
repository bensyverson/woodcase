//
//  PenSizelessFrameTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins what a `layout: "none"` frame with no width or height settles at and draws: Pen
/// settles it at 0×0 (an explicit `fit_content` at its fallback), draws its children
/// anyway at their own `x`/`y` unless it clips, paints its outer stroke and shadow around
/// the point, and gives it no room in a flex flow.
///
/// `render-sizeless-frames.pen` is a Pen-oracle reference (`scripts/pen-oracle <fixture>`,
/// 2x), written by `scripts/gen-sizeless-frames-fixture` (leaf Jg0BOv).
struct PenSizelessFrameTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Pen's exports are at 2x.
    private static let scale: CGFloat = 2

    /// How far a rect may sit from Pen's, in points.
    private static let tolerance = 0.5

    @Test("Layout matches Pen's settled layout for every sizeless frame, child and sibling")
    func layoutMatchesPen() throws {
        let document = try Self.document()
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixturesDir.appendingPathComponent("render-sizeless-frames.layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        for (id, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = try #require(actual[id], "no rect for \(id)")
            #expect(Self.distance(got, want) < Self.tolerance, "\(id): got \(got), Pen \(want)")
        }
    }

    /// MAE ceilings against Pen's 2x exports, set by the margin rule (max(measured×1.5,
    /// measured+0.25), `project/2026-09-26-mae-margin-rule.md`).
    ///
    /// Measured 2026-09-27 (leaf Jg0BOv, `swift test -j 3 --filter PenSizelessFrameTests`):
    /// `paint` 0.008, every other board 0.000. Before, with the frame at its children's
    /// union: `plain` 1.39 and `explicit` 2.03 (its fill drawn across them), `clip` 5.92
    /// (children drawn), `flex` 1.28 and `fitflex` 0.73 (the sibling and the parent moved),
    /// and `paint` 6.29 — 0.51 once the frame was 0×0, since Core Graphics stroked nothing
    /// along a path of no length, and so cast no shadow from the stroke either.
    private static let maeCeilings: [(board: String, ceiling: Double)] = [
        ("plain", 0.25), ("clip", 0.25), ("paint", 0.26), ("flex", 0.25), ("fitflex", 0.25), ("explicit", 0.25),
    ]

    @Test("The Core Graphics renderer draws each board within its ceiling of Pen's export", arguments: maeCeilings)
    func rendersLikePen(board: String, ceiling: Double) throws {
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "render-sizeless-frames-\(board)", fixturesDir: Self.fixturesDir
        ))
        let document = try Self.document()
        let node = try #require(document.children.first { $0.common.name == board })
        let rects = PenLayoutEngine.layout(document)
        let rendered = try #require(PenRenderer.render(
            document, layoutRects: rects,
            size: CGSize(width: CGFloat(reference.width) / Self.scale, height: CGFloat(reference.height) / Self.scale),
            scale: Self.scale, rootNodeID: node.id
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Sizeless frames \(board) MAE: \(mae)")
        #expect(mae < ceiling, "\(board): MAE \(mae)")
    }

    /// The largest difference between two rects' coordinates.
    private static func distance(_ a: PenRect, _ b: PenRect) -> Double {
        max(abs(a.x - b.x), abs(a.y - b.y), abs(a.width - b.width), abs(a.height - b.height))
    }

    /// The fixture, parsed and resolved as the renderer reads it.
    private static func document() throws -> PenDocument {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("render-sizeless-frames.pen"))
        return try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
    }
}
