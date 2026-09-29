//
//  PenMeshMalformedPointSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the renderer's handling of malformed mesh points against Pen's own exports.
///
/// `render-mesh-malformed-points.pen` holds one 150×100 3×2 mesh per artboard, each with
/// one vertex written in neither wire form. The references are Pen's PNG exports:
///
/// ```
/// scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-mesh-malformed-points.pen --scale 1,2 --accept-invalid
/// ```
///
/// (`pen` CLI 0.3.9, sandbox off). The first eight artboards are meshes Pen paints, with
/// the vertex where Pen places it; the last four are meshes Pen paints nothing for, and
/// their exports are fully transparent.
struct PenMeshMalformedPointSnapshotTests {
    private static let fixture = "render-mesh-malformed-points"
    static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The artboards Pen paints a mesh for.
    private static let painted = [
        "control", "string", "null", "no-position", "long", "null-number", "booleans", "long-handle",
    ]

    /// The artboards Pen paints nothing for.
    private static let undrawn = ["short", "string-position", "short-handle", "numeric-strings"]

    private static let scales = [1, 2]

    /// The pin for a painted board, measured 2026-09-26 with
    /// `swift test --filter PenMeshMalformedPointSnapshotTests` (0.30–0.35 at 1x and 2x):
    /// the mesh core's color-rounding bias against Pen's truncation, as
    /// `PenMeshFillSnapshotTests` explains, with room for the edge where the moved
    /// vertex bares part of the box.
    private static let paintedLimit = 0.40

    /// `booleans` measures 0.62 at 1x and 0.60 at 2x. Its `[true, false]` vertex lands
    /// on `[1, 0]`, on top of its right-hand neighbor, so patch (1, 0) collapses and
    /// patch (0, 0) overlaps it — the same disagreement over which patch covers a pixel
    /// that `mfold` shows. The placement itself is Pen's: Pen's export of this board is
    /// identical (MAE 0) to its export of the same mesh with the vertex written `[1, 0]`
    /// (`pen` CLI 0.3.9, scratch probe, 2026-09-26).
    private static let overlappingLimit = ["booleans": 0.65]

    @Test("The case lists name every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.painted + Self.undrawn)
    }

    @Test("A file with malformed mesh points decodes, and each point writes back as written")
    func decodesAndRoundTrips() throws {
        let url = Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
        let data = try Data(contentsOf: url)
        let document = try PenParser.parse(data)
        let reparsed = try PenParser.parse(JSONEncoder().encode(document))
        #expect(reparsed == document)
        let raw = try JSONDecoder().decode(AnyCodable.self, from: data)
        guard case let .dictionary(root) = raw, case let .array(children) = root["children"] else {
            Issue.record("fixture has no children")
            return
        }
        for (node, child) in zip(document.children, children) {
            guard case let .frame(frame) = node.kind, case let .meshGradient(mesh) = frame.fills?.all.first,
                  case let .dictionary(object) = child, case let .dictionary(fill) = object["fill"],
                  case let .array(points) = fill["points"]
            else {
                Issue.record("\(node.id) is not a frame with a mesh fill")
                continue
            }
            let written = try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(mesh.points))
            #expect(written == .array(points), "\(node.id)")
        }
    }

    @Test("Each painted mesh places every vertex where Pen's own re-save puts it")
    func placementsMatchPensResave() throws {
        let authored = try meshes(in: "\(Self.fixture).pen")
        let resaved = try meshes(in: "\(Self.fixture).pen-saved.pen")
        for name in Self.painted {
            let ours = try PenMeshGrid(#require(authored[name])).vertices
            let pens = try PenMeshGrid(#require(resaved[name])).vertices
            #expect(ours.map(\.position) == pens.map(\.position), "\(name)")
            #expect(ours.map(\.handles) == pens.map(\.handles), "\(name)")
        }
    }

    /// Every artboard's mesh fill in a fixture file, by artboard name.
    private func meshes(in file: String) throws -> [String: PenFill.PenMeshGradientFill] {
        let data = try Data(contentsOf: Self.fixturesDir.appendingPathComponent(file))
        var result: [String: PenFill.PenMeshGradientFill] = [:]
        for node in try PenParser.parse(data).children {
            if case let .frame(frame) = node.kind, case let .meshGradient(mesh) = frame.fills?.all.first,
               let name = node.common.name
            {
                result[name] = mesh
            }
        }
        return result
    }

    @Test("A mesh Pen paints matches its export", arguments: painted, scales)
    func paintedMatchesPen(artboard: String, scale: Int) async throws {
        let mae = try meanAbsoluteError(artboard, scale)
        let limit = Self.overlappingLimit[artboard] ?? Self.paintedLimit
        print("Malformed mesh point \(artboard) @\(scale)x MAE: \(String(format: "%.4f", mae))")
        await MAEReport.shared.record(id: "mesh-malformed-\(artboard)@\(scale)x", mae: mae, limit: limit)
        #expect(mae <= limit, "\(artboard) @\(scale)x: MAE \(mae), pinned at \(limit)")
    }

    @Test("A mesh Pen paints nothing for draws nothing", arguments: undrawn, scales)
    func undrawnMatchesPen(artboard: String, scale: Int) throws {
        #expect(try meanAbsoluteError(artboard, scale) == 0)
    }

    private func meanAbsoluteError(_ artboard: String, _ scale: Int) throws -> Double {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        return PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
    }
}
