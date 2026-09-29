//
//  MeshFoldDetector.swift
//  Woodcase
//

import Foundation

/// Finds the patches of a mesh gradient that fold over themselves.
///
/// A patch is the bicubic Bézier surface between four neighboring vertices, built
/// from their positions and handles the way Pen builds it (the control net and its
/// zero-twist interior points are in `project/2026-09-26-mesh-gradients.md` §1). It
/// **folds** where the surface turns over: where the map from the patch's own
/// parameters `(u, v)` to the node's unit square changes orientation, so one part of
/// the patch paints over another and part of the box is left bare.
///
/// ## The test
///
/// An unfolded grid is oriented like the node itself — `u` runs right, `v` runs down —
/// so the cross product of the two partial derivatives, `∂S/∂u × ∂S/∂v`, is positive
/// everywhere on it. The detector samples that Jacobian on a
/// (``samplesPerSide`` + 1)² grid of parameters per patch, edges included, and reports
/// a patch whose most negative sample is deeper than ``visibleDepth`` times the
/// patch's mean sample. A zero at a vertex whose handle is zero-length is a pinch, not
/// a fold, and is not reported.
///
/// The depth threshold is what makes the test practical rather than pedantic. The
/// report's `mwarp` probe mesh, which Pen draws cleanly, has a patch whose Jacobian
/// dips to −0.0008 against a mean of 0.13 at 3 of its 1,089 samples: a fold, strictly,
/// but a sliver no export shows. Real folds sit far past the threshold — the report's
/// `mfold` reaches −1.28 against a mean of 0.62, a vertex dragged past its neighbor
/// −0.27 against 0.05. (Figures from a scratch Python port of this test, run over the
/// meshes in `project/2026-09-26-mesh-gradients.md` Appendix A.)
///
/// Sampling is a practical test, not a proof: a fold narrower than one sample step
/// (1/32 of a patch) can slip between samples, and two patches that overlap each
/// other without either turning over — a vertex dragged across a whole neighboring
/// patch — are not reported. Both are rarer than a handle dragged too far, which is
/// the case this exists for.
enum MeshFoldDetector {
    /// One patch of the grid, by the column and row of its top-left vertex (0-based).
    struct Patch: Friendly {
        /// The column of the patch's top-left vertex.
        let column: Int

        /// The row of the patch's top-left vertex.
        let row: Int
    }

    /// How many parameter samples a patch is checked at along each side.
    ///
    /// Pen tessellates a patch into 32 cells a side, so a fold narrower than that is
    /// one it does not draw either.
    static let samplesPerSide = 32

    /// How deep, as a fraction of the patch's mean Jacobian, the most negative sample
    /// must reach before the fold is one a render shows.
    static let visibleDepth = 0.05

    /// The patches of a fill that fold over themselves, in row-major order.
    ///
    /// Each vertex is tested where the renderer draws it (``PenMeshGrid/init(_:)``), so a
    /// malformed point Pen places is tested at the place Pen gives it.
    ///
    /// - Parameter fill: The mesh to test.
    /// - Returns: The folded patches, or none when Pen would not draw the grid at all — a
    ///   missing or mismatched count, or a point Pen cannot place, is a different finding,
    ///   and there is no surface to test until it is fixed.
    static func foldedPatches(in fill: PenFill.PenMeshGradientFill) -> [Patch] {
        guard let grid = try? PenMeshGrid(fill) else { return [] }
        var folded: [Patch] = []
        for row in 0 ..< grid.patchRows {
            for column in 0 ..< grid.patchColumns {
                let net = controlNet(
                    topLeft: grid.vertex(column: column, row: row),
                    topRight: grid.vertex(column: column + 1, row: row),
                    bottomLeft: grid.vertex(column: column, row: row + 1),
                    bottomRight: grid.vertex(column: column + 1, row: row + 1)
                )
                if folds(net) {
                    folded.append(Patch(column: column, row: row))
                }
            }
        }
        return folded
    }

    // MARK: - The surface

    /// A vertex with every handle resolved.
    private typealias Vertex = PenMeshGrid.Vertex

    /// A point in unit space, as a plain pair for the arithmetic.
    private typealias Point = (x: Double, y: Double)

    /// The 4×4 control net of the patch between four vertices, rows running down.
    ///
    /// The edge rows and columns come from the corners and their handles; each
    /// interior point is the zero-twist parallelogram of its corner's two handles.
    private static func controlNet(
        topLeft tl: Vertex, topRight tr: Vertex, bottomLeft bl: Vertex, bottomRight br: Vertex
    ) -> [[Point]] {
        func at(_ vertex: Vertex, _ handles: PenMeshPoint.Vector...) -> Point {
            handles.reduce((vertex.position.x, vertex.position.y)) { ($0.x + $1.x, $0.y + $1.y) }
        }
        return [
            [at(tl), at(tl, tl.handles.right), at(tr, tr.handles.left), at(tr)],
            [
                at(tl, tl.handles.bottom), at(tl, tl.handles.right, tl.handles.bottom),
                at(tr, tr.handles.left, tr.handles.bottom), at(tr, tr.handles.bottom),
            ],
            [
                at(bl, bl.handles.top), at(bl, bl.handles.right, bl.handles.top),
                at(br, br.handles.left, br.handles.top), at(br, br.handles.top),
            ],
            [at(bl), at(bl, bl.handles.right), at(br, br.handles.left), at(br)],
        ]
    }

    /// Whether the surface's Jacobian turns visibly negative where it is sampled.
    ///
    /// A patch whose mean is itself zero or negative is folded through and through,
    /// so any negative sample counts.
    private static func folds(_ net: [[Point]]) -> Bool {
        let steps = samplesPerSide
        var lowest = Double.infinity
        var total = 0.0
        for j in 0 ... steps {
            let v = Double(j) / Double(steps)
            for i in 0 ... steps {
                let u = Double(i) / Double(steps)
                let du = derivative(net, u: u, v: v, alongU: true)
                let dv = derivative(net, u: u, v: v, alongU: false)
                let jacobian = du.x * dv.y - du.y * dv.x
                lowest = min(lowest, jacobian)
                total += jacobian
            }
        }
        let mean = total / Double((steps + 1) * (steps + 1))
        return lowest < 0 && lowest < -visibleDepth * max(mean, 0)
    }

    /// The partial derivative of the tensor-product surface along `u` or along `v`.
    private static func derivative(_ net: [[Point]], u: Double, v: Double, alongU: Bool) -> Point {
        let bu = alongU ? bernsteinDerivative(u) : bernstein(u)
        let bv = alongU ? bernstein(v) : bernsteinDerivative(v)
        var x = 0.0
        var y = 0.0
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                let weight = bv[row] * bu[column]
                x += weight * net[row][column].x
                y += weight * net[row][column].y
            }
        }
        return (x, y)
    }

    /// The four cubic Bernstein polynomials at `t`.
    private static func bernstein(_ t: Double) -> [Double] {
        let s = 1 - t
        return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t]
    }

    /// The derivatives of the four cubic Bernstein polynomials at `t`.
    private static func bernsteinDerivative(_ t: Double) -> [Double] {
        let s = 1 - t
        return [-3 * s * s, 3 * s * s - 6 * t * s, 6 * t * s - 3 * t * t, 3 * t * t]
    }
}
