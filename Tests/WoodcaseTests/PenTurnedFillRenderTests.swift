//
//  PenTurnedFillRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the Core Graphics renderer on turned `fill_container` flex children against Pen's
/// settled render: Pen fills the child's unturned box — the main-axis share, the container's
/// inner cross size, or both — and gives it the bounds of the turned result as its slot.
///
/// `render-turned-fill.pen` is written by `scripts/gen-turned-fill-fixture`; its layout and
/// 2x exports come from `scripts/pen-oracle <fixture> --scale 2 --settle`, so both are Pen's
/// layout after a relayout, not the first pass after load, which differs here on five
/// containers (`scripts/pen-settle`; PenInteroperability.md, "Kept Divergences").
struct PenTurnedFillRenderTests {
    private static let fixture = "render-turned-fill"

    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Pen's exports are at 2x.
    private static let scale: CGFloat = 2

    /// How far a rect may sit from Pen's, in points.
    private static let tolerance = 0.01

    @Test("Layout matches Pen's settled layout")
    func layoutMatchesPen() throws {
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixturesDir.appendingPathComponent("\(Self.fixture).layout.json"))
        )
        let actual = try PenLayoutEngine.layout(Self.document())
        for (id, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = try #require(actual[id], "no rect for \(id)")
            let off = max(abs(got.x - want.x), abs(got.y - want.y), abs(got.width - want.width), abs(got.height - want.height))
            #expect(off <= Self.tolerance, "\(id): got \(got), Pen \(want)")
        }
    }

    /// The boards, each with its MAE ceiling against Pen's 2x export, set by the margin rule
    /// (max(measured × 1.5, measured + 0.25), `project/2026-09-26-mae-margin-rule.md`).
    ///
    /// Measured 2026-09-28 (leaf ozlazY, `swift test -j 3 --filter PenTurnedFillRenderTests`):
    /// 0.000 (the quarter turns) to 0.018 (`row-main-center-30`), the anti-aliased edges of
    /// the turned child; the rule gives 0.25–0.27, so every board shares 0.27.
    static let boards: [(board: String, ceiling: Double)] = [
        "row-main-30", "row-main-90", "row-main-center-30", "row-main-two-30", "col-main-30", "col-main-90",
        "row-cross-30", "row-cross-90", "col-cross-30", "row-both-30", "col-both-60", "row-cross-fit-30",
    ].map { ($0, 0.27) }

    @Test("The Core Graphics renderer draws each board within its ceiling of Pen's export", arguments: boards)
    func rendersLikePen(board: String, ceiling: Double) throws {
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(board)", fixturesDir: Self.fixturesDir
        ))
        let document = try Self.document()
        let node = try #require(document.children.first { $0.common.name == board })
        let rects = PenLayoutEngine.layout(document)
        let rect = try #require(rects[node.id])
        let rendered = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: Self.scale, rootNodeID: node.id
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Turned fill \(board) MAE: \(mae)")
        #expect(mae < ceiling, "\(board): MAE \(mae)")
    }

    /// The fixture, parsed and resolved as the renderer reads it.
    private static func document() throws -> PenDocument {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        return try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
    }
}
