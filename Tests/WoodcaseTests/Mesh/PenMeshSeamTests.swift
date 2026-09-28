//
//  PenMeshSeamTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A translucent mesh must have no seams: along every edge patches and triangles share,
/// each pixel is covered exactly once, so its alpha equals the alpha in a patch interior.
///
/// A doubly covered pixel would composite to a higher alpha, an uncovered one to zero.
/// Every mesh here is one translucent colour everywhere, so any alpha other than the
/// colour's own is a coverage error.
struct PenMeshSeamTests {
    typealias Support = MeshTestSupport
    typealias Vector = PenMeshPoint.Vector

    private static let translucent = PenMeshColor(red: 0.2, green: 0.4, blue: 1, alpha: 0.5)

    /// 0.5 × 255 = 127.5, which rounds to 128.
    private static let interiorAlpha: UInt8 = 128

    private func assertUniform(_ raster: PenMeshRaster, sourceLocation: SourceLocation = #_sourceLocation) {
        var wrong: [String] = []
        for y in 0 ..< raster.height {
            for x in 0 ..< raster.width where raster.pixel(x: x, y: y).alpha != Self.interiorAlpha {
                wrong.append("(\(x), \(y)) α=\(raster.pixel(x: x, y: y).alpha)")
            }
        }
        #expect(wrong.isEmpty, "\(wrong.count) pixels off the interior alpha: \(wrong.prefix(8))", sourceLocation: sourceLocation)
    }

    private func uniform(columns: Int, rows: Int) throws -> PenMeshGrid {
        try Support.regularGrid(columns: columns, rows: rows, colors: Array(repeating: Self.translucent, count: columns * rows))
    }

    @Test("Interior patch edges on pixel boundaries", arguments: [(100, 100), (120, 60)])
    func edgesBetweenPixels(width: Int, height: Int) throws {
        try assertUniform(PenMeshRasterizer.rasterize(uniform(columns: 3, rows: 3), width: width, height: height))
    }

    @Test("Interior patch edges through pixel centres", arguments: [(101, 101), (41, 81)])
    func edgesThroughCentres(width: Int, height: Int) throws {
        // With odd sizes the patch edges at u = ½ and v = ½ run exactly through a column
        // and a row of pixel centres, where only the top-left rule decides ownership.
        try assertUniform(PenMeshRasterizer.rasterize(uniform(columns: 3, rows: 3), width: width, height: height))
    }

    @Test("The interior alpha is what the seam pixels are compared against")
    func interiorIsTheColour() throws {
        let raster = try PenMeshRasterizer.rasterize(uniform(columns: 3, rows: 3), width: 101, height: 101)
        let centre = raster.pixel(x: 25, y: 25)
        #expect(centre.alpha == Self.interiorAlpha)
        #expect(raster.pixel(x: 50, y: 25).alpha == centre.alpha)
        #expect(raster.pixel(x: 25, y: 50).alpha == centre.alpha)
        #expect(raster.pixel(x: 50, y: 50).alpha == centre.alpha)
    }

    @Test("Curved shared edges of a warped mesh are seamless too")
    func warpedEdges() throws {
        let base = try uniform(columns: 3, rows: 3)
        var vertices = base.vertices
        vertices[4].position = Vector(0.3, 0.7)
        vertices[4].handles = PenMeshPoint.Handles(
            left: Vector(-0.2, 0.1),
            right: Vector(0.2, -0.1),
            top: Vector(0.05, -0.3),
            bottom: Vector(-0.05, 0.3)
        )
        let grid = try PenMeshGrid(columns: 3, rows: 3, vertices: vertices)
        for size in [(240, 240), (97, 131)] {
            assertUniform(PenMeshRasterizer.rasterize(grid, width: size.0, height: size.1))
        }
    }

    @Test("A 4×3 mesh with unequal patches is seamless")
    func unequalPatches() throws {
        let base = try uniform(columns: 4, rows: 3)
        var vertices = base.vertices
        vertices[5].position = Vector(0.45, 0.35)
        vertices[6].position = Vector(0.6, 0.7)
        vertices[6].handles.right = Vector(0.15, 0.2)
        vertices[6].handles.left = Vector(-0.1, -0.05)
        let grid = try PenMeshGrid(columns: 4, rows: 3, vertices: vertices)
        assertUniform(PenMeshRasterizer.rasterize(grid, width: 320, height: 200))
    }
}
