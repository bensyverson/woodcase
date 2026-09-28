import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A per-side stroke width on a shape that has no box sides — an ellipse, a polygon, a path,
/// a line — against Pen's own renders.
///
/// Pen strokes such a shape with one uniform stroke of the **top** width and ignores the
/// other three sides; `strokeAlignment`, the join and the cap apply as they do to a uniform
/// stroke, and a missing top draws nothing. `render-per-side-shapes.pen` pins it: widths
/// t12 r2 b6 l0 and t2 r10 b4 l6 under the default alignment, t12 r2 b6 l0 inside and
/// outside, an ellipse with no top, and a line (`scripts/pen-oracle … --scale 2`;
/// finding F6 of `project/2026-09-27-fidelity-gaps.md`).
struct PenPerSideShapesTests {
    private static let fixture = "render-per-side-shapes"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order.
    private static let artboards = [
        "ellip-top12", "polyg-top12", "pathx-top12", "ellip-top2", "polyg-top2", "pathx-top2",
        "ellip-inner", "polyg-inner", "pathx-inner", "ellip-outer", "polyg-outer", "pathx-outer",
        "ellip-notop", "line-top12",
    ]

    /// The criterion: within MAE 0.5 of Pen's export.
    private static let limit = 0.5

    // MARK: - Against Pen

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each board draws within MAE 0.5 of Pen's export", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: 2
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Per-side shape \(artboard) MAE: \(mae)")
        #expect(mae < Self.limit, "\(artboard): MAE \(mae)")
    }

    // MARK: - The rule

    /// The one child of a document's one frame, with `keys` added to a 140×100 node of `type`.
    private func node(_ type: String, _ keys: String) throws -> PenNode {
        let document = try PenParser.parse("""
        {"version": "2.17", "children": [{"type": "frame", "id": "Brd01", "layout": "none", "width": 200, "height": 160,
          "children": [{"type": "\(type)", "id": "Shp01", "x": 30, "y": 30, "width": 140, "height": 100, \(keys)}]}]}
        """)
        guard case let .frame(board) = document.children.first?.kind else { throw CancellationError() }
        return try #require(board.children?.first)
    }

    /// The width `node`'s stroke is drawn at, as ``PenStrokable/drawn(on:)`` gives it.
    private func drawnWidth(_ node: PenNode) throws -> PenStrokeWidth? {
        let stroke: any PenStrokable = switch node.kind {
        case let .ellipse(data): data
        case let .polygon(data): data
        case let .path(data): data
        case let .line(data): data
        case let .rectangle(data): data
        case let .frame(data): data
        default: throw CancellationError()
        }
        return stroke.drawn(on: node).strokeWidth
    }

    private static let perSide = ##""stroke": "#FF0000", "strokeWidth": {"top": 12, "right": 2, "bottom": 6, "left": 0}"##

    @Test("A per-side width is drawn as the top width all round on an ellipse, a polygon, a path and a line; a box keeps its sides")
    func onlySidelessShapesTakeTheTop() throws {
        for type in ["ellipse", "polygon", "path", "line"] {
            #expect(try drawnWidth(node(type, Self.perSide)) == .uniform(.literal(12)), "\(type)")
        }
        for type in ["rectangle", "frame"] {
            let drawn = try drawnWidth(node(type, Self.perSide))
            guard case .perSide = drawn else {
                Issue.record("\(type): \(String(describing: drawn))")
                continue
            }
        }
        // A uniform width, and no width, are unchanged.
        #expect(try drawnWidth(node("ellipse", ##""stroke": "#FF0000", "strokeWidth": 3"##)) == .uniform(.literal(3)))
        #expect(try drawnWidth(node("ellipse", ##""stroke": "#FF0000""##)) == nil)
    }

    @Test("A per-side width with no top draws nothing on an ellipse")
    func missingTopIsZero() throws {
        let node = try node("ellipse", ##""stroke": "#FF0000", "strokeWidth": {"right": 10, "bottom": 4, "left": 6}"##)
        #expect(try drawnWidth(node) == .uniform(.literal(0)))
    }

    @Test("A top width held in a variable stays a variable")
    func variableTop() throws {
        let node = try node("polygon", ##""stroke": "#FF0000", "strokeWidth": {"top": "$hairline", "left": 3}"##)
        #expect(try drawnWidth(node) == .uniform(.variable("hairline")))
    }

    @Test("An ellipse's shadow silhouette grows by half the top width of a centred per-side stroke")
    func silhouetteTakesTheTop() throws {
        let node = try node("ellipse", Self.perSide)
        let rect = PenRect(x: 30, y: 30, width: 140, height: 100)
        let silhouette = try #require(PenShadowSilhouette.path(for: node, rect: rect))
        let bounds = silhouette.path.boundingBox
        #expect(abs(bounds.minX - 24) < 0.01 && abs(bounds.maxX - 176) < 0.01, "\(bounds)")
        #expect(abs(bounds.minY - 24) < 0.01 && abs(bounds.maxY - 136) < 0.01, "\(bounds)")
    }
}
