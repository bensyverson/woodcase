//
//  PenMeshRasterizer.swift
//  Woodcase
//

import Foundation

/// Draws a mesh gradient into a ``PenMeshRaster``, on the CPU, without CoreGraphics.
///
/// Each triangle is Gouraud-shaded: its vertex colors are premultiplied, then
/// interpolated linearly and sampled at pixel centers. Coverage follows the top-left
/// rule on exact fixed-point edge functions, so a pixel center on an edge two triangles
/// share belongs to exactly one of them: a translucent mesh has no seams, neither
/// doubled nor missing pixels. Triangles composite source-over in the tessellation's
/// order, so where a folded mesh overlaps itself the later patch covers the earlier one.
///
/// There is no anti-aliasing. A mesh with default edge points covers its box exactly,
/// and the renderer clips the raster to the node's (anti-aliased) path. Area the mesh
/// leaves uncovered stays transparent.
///
/// The fill's `opacity` and blend mode are the caller's to apply when compositing.
public enum PenMeshRasterizer {
    /// Rasterizes a tessellation into a buffer of the given size.
    ///
    /// - Parameters:
    ///   - tessellation: Triangles in device pixels, from the box's top-left corner.
    ///   - width: The buffer width in pixels.
    ///   - height: The buffer height in pixels.
    /// - Returns: The premultiplied RGBA8 raster; transparent where nothing is drawn.
    public static func rasterize(_ tessellation: PenMeshTessellation, width: Int, height: Int) -> PenMeshRaster {
        let width = max(width, 0)
        let height = max(height, 0)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard width > 0, height > 0 else { return PenMeshRaster(width: width, height: height, pixels: pixels) }
        let corners = zip(tessellation.positions, tessellation.colors).map { Corner($0, color: $1) }
        let indices = tessellation.indices
        pixels.withUnsafeMutableBufferPointer { buffer in
            for start in stride(from: 0, to: indices.count - 2, by: 3) {
                let first = Int(indices[start]), second = Int(indices[start + 1]), third = Int(indices[start + 2])
                guard max(first, second, third) < corners.count,
                      let a = corners[first], let b = corners[second], let c = corners[third]
                else { continue }
                fill(a, b, c, into: buffer, width: width, height: height)
            }
        }
        return PenMeshRaster(width: width, height: height, pixels: pixels)
    }

    /// Tessellates a grid for a box of the given pixel size and rasterizes it.
    ///
    /// - Parameters:
    ///   - grid: The mesh.
    ///   - width: The box width in device pixels.
    ///   - height: The box height in device pixels.
    ///   - tessellator: The tessellator, carrying the tolerances to meet.
    /// - Returns: The premultiplied RGBA8 raster of the whole box.
    public static func rasterize(
        _ grid: PenMeshGrid,
        width: Int,
        height: Int,
        tessellator: PenMeshTessellator = PenMeshTessellator()
    ) -> PenMeshRaster {
        let tessellation = tessellator.tessellate(grid, width: Double(max(width, 0)), height: Double(max(height, 0)))
        return rasterize(tessellation, width: width, height: height)
    }
}
