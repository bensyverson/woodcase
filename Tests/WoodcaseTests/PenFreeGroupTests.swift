//
//  PenFreeGroupTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins where a group lands and where its children are drawn: a group's rect is the true
/// union of its children — left of and above its anchor when they reach there — and its
/// children stay placed from the anchor.
///
/// `render-free-groups.pen` is a Pen-oracle reference (`scripts/pen-oracle <fixture>`, 2x),
/// written by `scripts/gen-free-groups-fixture`: groups with children at
/// positive and negative offsets, placed freely and in a flex flow, turned, flipped and
/// turned, nested, blurred, shadowed, and one at the root.
struct PenFreeGroupTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Pen's exports are at 2x.
    private static let scale: CGFloat = 2

    /// How far a rect may sit from Pen's, in points.
    private static let tolerance = 0.5

    @Test("Layout matches Pen's settled layout for every group and child")
    func layoutMatchesPen() throws {
        let document = try Self.document("render-free-groups")
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixturesDir.appendingPathComponent("render-free-groups.layout.json"))
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
    /// Measured 2026-09-27 (leaf cqBw2i, `swift test -j 3 --filter PenFreeGroupTests`): `pos`,
    /// `neg`, `flex`, `nest` and `root` 0.000, `rot` 0.005, `flexrot` 0.004, `flip` 0.007,
    /// `blur` 0.051, `shadow` 0.049. Before, with a group's rect pinned at its anchor: `flex`
    /// 2.55, `flexrot` 5.53, `blur` 1.46 (the blur buffer cut off what reached left of the
    /// anchor) and `root` 89.0 (the export's canvas started at the anchor); the other six
    /// already matched, since a free group's children were drawn from its anchor either way.
    private static let maeCeilings: [(board: String, ceiling: Double)] = [
        ("pos", 0.25), ("neg", 0.25), ("flex", 0.25), ("rot", 0.25), ("nest", 0.25),
        ("flexrot", 0.25), ("flip", 0.26), ("blur", 0.30), ("shadow", 0.30), ("root", 0.25),
    ]

    @Test("The Core Graphics renderer draws each board within its ceiling of Pen's export", arguments: maeCeilings)
    func rendersLikePen(board: String, ceiling: Double) throws {
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "render-free-groups-\(board)", fixturesDir: Self.fixturesDir
        ))
        let document = try Self.document("render-free-groups")
        let node = try #require(document.children.first { $0.common.name == board })
        let rects = PenLayoutEngine.layout(document)
        let rendered = try #require(PenRenderer.render(
            document, layoutRects: rects,
            size: CGSize(width: CGFloat(reference.width) / Self.scale, height: CGFloat(reference.height) / Self.scale),
            scale: Self.scale, rootNodeID: node.id
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Free groups \(board) MAE: \(mae)")
        #expect(mae < ceiling, "\(board): MAE \(mae)")
    }

    /// A group's children are placed from its anchor, not from its rect's corner: `neg`'s
    /// group sits at `(100, 100)` in a board at `(400, 0)`, and its children at `(-30, -20)`
    /// and `(20, 10)` from that anchor — where Pen's export draws them.
    @Test("absoluteRects places a group's children from its anchor")
    func absoluteRectsPlaceGroupChildrenFromTheAnchor() throws {
        let document = try Self.document("render-free-groups")
        let rects = PenLayoutEngine.layout(document)
        let placed = PenLayoutEngine.absoluteRects(under: "Gneg", in: document, layoutRects: rects)
        try Self.expect(placed, "GnegG", PenRect(x: 470, y: 80, width: 90, height: 70))
        try Self.expect(placed, "GnegA", PenRect(x: 470, y: 80, width: 40, height: 40))
        try Self.expect(placed, "GnegB", PenRect(x: 520, y: 110, width: 40, height: 40))

        // A group in a flex flow sits in its slot; its anchor is the slot less its union's
        // corner, `(70, 20) - (-10, -10)`.
        let flex = PenLayoutEngine.absoluteRects(under: "Gflex", in: document, layoutRects: rects)
        try Self.expect(flex, "GflexGa", PenRect(x: 870, y: 20, width: 30, height: 30))
        try Self.expect(flex, "GflexGb", PenRect(x: 900, y: 50, width: 30, height: 30))

        // A nested group's anchor is its own `x`/`y` from its parent group's anchor.
        let nest = PenLayoutEngine.absoluteRects(under: "Gnest", in: document, layoutRects: rects)
        try Self.expect(nest, "GnestHa", PenRect(x: 1660, y: 90, width: 40, height: 40))
        try Self.expect(nest, "GnestHb", PenRect(x: 1700, y: 130, width: 10, height: 10))
    }

    /// A turned node's children are turned with it. `nested`'s frame turns 25° about its
    /// anchor `(100, 50)` in a board at `(900, 400)`; its 40×20 child at `(0, 0)` covers the
    /// bounds of that box turned about the same anchor — 44.70×35.03, 16.90 above the anchor —
    /// which is where Pen's export draws its orange (x 100…144.5, y 33.5…68 at 2x, to the
    /// pixel). `rot`'s group turns 30° about `(100, 100)`; its 60×20 child at the anchor
    /// covers x 100…161.96, y 70…117.32 (Pen: 100.5…161.5, 70.5…117).
    @Test("absoluteRects turns a turned node's children with it")
    func absoluteRectsTurnChildrenOfATurnedNode() throws {
        let transformed = try Self.document("render-transformed-free")
        let nested = PenLayoutEngine.absoluteRects(
            under: "Nest1", in: transformed, layoutRects: PenLayoutEngine.layout(transformed)
        )
        let s25 = sin(25 * Double.pi / 180), c25 = cos(25 * Double.pi / 180)
        try Self.expect(nested, "N1c", PenRect(
            x: 1000, y: 450 - 40 * s25, width: 40 * c25 + 20 * s25, height: 40 * s25 + 20 * c25
        ))

        let groups = try Self.document("render-free-groups")
        let rot = PenLayoutEngine.absoluteRects(
            under: "Grot", in: groups, layoutRects: PenLayoutEngine.layout(groups)
        )
        let s30 = 0.5, c30 = cos(30 * Double.pi / 180)
        try Self.expect(rot, "GrotA", PenRect(
            x: 1300, y: 100 - 60 * s30, width: 60 * c30 + 20 * s30, height: 60 * s30 + 20 * c30
        ))
    }

    /// The largest difference between two rects' coordinates.
    private static func distance(_ a: PenRect, _ b: PenRect) -> Double {
        max(abs(a.x - b.x), abs(a.y - b.y), abs(a.width - b.width), abs(a.height - b.height))
    }

    /// Expects `rects[id]` within 0.01 pt of `want`.
    private static func expect(
        _ rects: [String: PenRect], _ id: String, _ want: PenRect, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let got = try #require(rects[id], "no rect for \(id)", sourceLocation: sourceLocation)
        #expect(distance(got, want) < 0.01, "\(id): got \(got), want \(want)", sourceLocation: sourceLocation)
    }

    /// A fixture, parsed and resolved as the renderer reads it.
    private static func document(_ fixture: String) throws -> PenDocument {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        return try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
    }
}
