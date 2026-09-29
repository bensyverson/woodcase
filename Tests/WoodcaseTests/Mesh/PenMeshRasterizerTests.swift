//
//  PenMeshRasterizerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Coverage and shading of the CPU rasterizer.
struct PenMeshRasterizerTests {
    typealias Support = MeshTestSupport
    typealias Vector = PenMeshPoint.Vector

    private func triangle(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, color: PenMeshColor) -> PenMeshTessellation {
        PenMeshTessellation(positions: [a, b, c], colors: [color, color, color], indices: [0, 1, 2], columnSubdivisions: [], rowSubdivisions: [])
    }

    @Test("The raster has the requested size and is transparent where nothing is drawn")
    func sizeAndClear() {
        let raster = PenMeshRasterizer.rasterize(.empty, width: 7, height: 3)
        #expect(raster.width == 7)
        #expect(raster.height == 3)
        #expect(raster.pixels.count == 7 * 3 * 4)
        #expect(raster.pixels.allSatisfy { $0 == 0 })
    }

    @Test("A triangle covers exactly the pixel centers inside it, whichever way it winds")
    func triangleCoverage() {
        // The lower-left half of a 4×4 box: centers with x < y are inside and x > y
        // outside. The diagonal x == y runs through centers; it is not a top-left edge
        // of this triangle, so those centers belong to its neighbor.
        let windings = [[SIMD2(0.0, 0), SIMD2(0.0, 4), SIMD2(4.0, 4)], [SIMD2(0.0, 0), SIMD2(4.0, 4), SIMD2(0.0, 4)]]
        let rasters = windings.map { PenMeshRasterizer.rasterize(triangle($0[0], $0[1], $0[2], color: Support.red), width: 4, height: 4) }
        #expect(rasters[0] == rasters[1])
        for y in 0 ..< 4 {
            for x in 0 ..< 4 {
                #expect(rasters[0].pixel(x: x, y: y).alpha == (x < y ? 255 : 0))
            }
        }
    }

    @Test("Two triangles sharing a diagonal through pixel centers cover each center once")
    func sharedDiagonal() {
        let half = PenMeshColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let mesh = PenMeshTessellation(
            positions: [SIMD2(0, 0), SIMD2(4, 0), SIMD2(0, 4), SIMD2(4, 4)],
            colors: Array(repeating: half, count: 4),
            indices: [0, 3, 2, 0, 1, 3],
            columnSubdivisions: [1],
            rowSubdivisions: [1]
        )
        let raster = PenMeshRasterizer.rasterize(mesh, width: 4, height: 4)
        for y in 0 ..< 4 {
            for x in 0 ..< 4 {
                #expect(raster.pixel(x: x, y: y) == PenMeshRaster.Pixel(red: 0, green: 0, blue: 128, alpha: 128))
            }
        }
    }

    @Test("A default opaque mesh covers its whole box")
    func opaqueCoversBox() throws {
        let raster = try PenMeshRasterizer.rasterize(Support.fourColor(), width: 37, height: 23)
        #expect(raster.width == 37 && raster.height == 23)
        for y in 0 ..< 23 {
            for x in 0 ..< 37 {
                #expect(raster.pixel(x: x, y: y).alpha == 255)
            }
        }
    }

    @Test("Pixels take the patch color at their center, within one 8-bit step")
    func shading() throws {
        let grid = try Support.fourColor(handles: Support.thirdHandles(columns: 2, rows: 2))
        let size = 64
        let raster = PenMeshRasterizer.rasterize(grid, width: size, height: size)
        var worst = 0
        for y in 0 ..< size {
            for x in 0 ..< size {
                // Straight third-length handles make position(u, v) = (u, v), so a pixel
                // center's parameters are its unit coordinates.
                let u = (Double(x) + 0.5) / Double(size)
                let v = (Double(y) + 0.5) / Double(size)
                let expected = Support.bilinear(
                    Support.red, Support.green, Support.blue, Support.yellow,
                    s: Support.smoothstep(u), t: Support.smoothstep(v)
                )
                let pixel = raster.pixel(x: x, y: y)
                worst = max(worst, abs(Int(pixel.red) - Int((expected.red * 255).rounded())))
                worst = max(worst, abs(Int(pixel.green) - Int((expected.green * 255).rounded())))
                worst = max(worst, abs(Int(pixel.blue) - Int((expected.blue * 255).rounded())))
            }
        }
        #expect(worst <= 1)
    }

    @Test("Vertex colors are premultiplied before they are interpolated")
    func premultipliedInterpolation() {
        // Opaque red to fully transparent green: premultiplied, the green never shows.
        let mesh = PenMeshTessellation(
            positions: [SIMD2(0, 0), SIMD2(2, 0), SIMD2(0, 1), SIMD2(2, 1)],
            colors: [Support.red, PenMeshColor(red: 0, green: 1, blue: 0, alpha: 0), Support.red, PenMeshColor(red: 0, green: 1, blue: 0, alpha: 0)],
            indices: [0, 3, 2, 0, 1, 3],
            columnSubdivisions: [1],
            rowSubdivisions: [1]
        )
        let raster = PenMeshRasterizer.rasterize(mesh, width: 2, height: 1)
        #expect(raster.pixel(x: 0, y: 0) == PenMeshRaster.Pixel(red: 191, green: 0, blue: 0, alpha: 191))
        #expect(raster.pixel(x: 1, y: 0) == PenMeshRaster.Pixel(red: 64, green: 0, blue: 0, alpha: 64))
    }

    @Test("Area the mesh leaves uncovered stays transparent")
    func uncovered() throws {
        let defaults = PenMeshPoint.Handles.defaults(columns: 2, rows: 2)
        let inset = [Vector(0.25, 0.25), Vector(0.75, 0.25), Vector(0.25, 0.75), Vector(0.75, 0.75)]
        let vertices = inset.map { PenMeshGrid.Vertex(position: $0, handles: .init(
            left: Vector(defaults.left.x / 2, 0), right: Vector(defaults.right.x / 2, 0),
            top: Vector(0, defaults.top.y / 2), bottom: Vector(0, defaults.bottom.y / 2)
        ), color: Support.blue) }
        let grid = try PenMeshGrid(columns: 2, rows: 2, vertices: vertices)
        let raster = PenMeshRasterizer.rasterize(grid, width: 40, height: 40)
        #expect(raster.pixel(x: 2, y: 2).alpha == 0)
        #expect(raster.pixel(x: 37, y: 20).alpha == 0)
        #expect(raster.pixel(x: 20, y: 20) == PenMeshRaster.Pixel(red: 0, green: 0, blue: 255, alpha: 255))
    }

    @Test("Where a folded translucent mesh overlaps itself, the later triangles composite over the earlier")
    func foldsOverdraw() throws {
        let half = PenMeshColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        var grid = try Support.regularGrid(columns: 2, rows: 2, colors: Array(repeating: half, count: 4))
        var vertices = grid.vertices
        // The report's `mfold`: long handles fold the patch back over itself.
        vertices[0].handles.right = Vector(1.2, 0.6)
        vertices[0].handles.bottom = Vector(0.6, 1.2)
        vertices[3].handles.left = Vector(-1.2, -0.6)
        grid = try PenMeshGrid(columns: 2, rows: 2, vertices: vertices)
        let raster = PenMeshRasterizer.rasterize(grid, width: 100, height: 100)
        let alphas = Set(raster.pixels.enumerated().filter { $0.offset % 4 == 3 }.map(\.element))
        // Singly covered: 0.5 × 255 = 127.5 → 128. Doubly covered, source-over on the
        // 8-bit buffer as a GPU would: 127.5 + 128 × 0.5 = 191.5 → 192.
        #expect(alphas.contains(128))
        #expect(alphas.contains(192))
    }

    @Test("Triangles off the raster are clipped, not wrapped")
    func clipping() {
        let mesh = triangle(SIMD2(-10, -10), SIMD2(30, -10), SIMD2(-10, 30), color: Support.red)
        let raster = PenMeshRasterizer.rasterize(mesh, width: 8, height: 8)
        #expect(raster.pixel(x: 0, y: 0).alpha == 255)
        #expect(raster.pixel(x: 7, y: 7).alpha == 255)
        let far = triangle(SIMD2(100, 100), SIMD2(120, 100), SIMD2(100, 120), color: Support.red)
        #expect(PenMeshRasterizer.rasterize(far, width: 8, height: 8).pixels.allSatisfy { $0 == 0 })
    }
}
