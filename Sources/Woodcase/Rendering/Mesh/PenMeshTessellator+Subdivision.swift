//
//  PenMeshTessellator+Subdivision.swift
//  Woodcase
//

import Foundation

public extension PenMeshTessellator {
    /// How many cells a patch is cut into along each axis.
    struct Subdivision: Friendly {
        /// Creates a subdivision.
        ///
        /// - Parameters:
        ///   - u: The cell count across.
        ///   - v: The cell count down.
        public init(u: Int, v: Int) {
            self.u = u
            self.v = v
        }

        /// The cell count across, along `u`.
        public var u: Int

        /// The cell count down, along `v`.
        public var v: Int
    }

    /// The cell counts one patch needs on its own to stay within both tolerances at the
    /// given box size.
    ///
    /// ``tessellate(_:width:height:)`` then takes the largest count in each patch
    /// column and row.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - width: The node box's width in device pixels.
    ///   - height: The node box's height in device pixels.
    /// - Returns: The counts, each in `1...maximumSubdivisions`.
    func subdivision(for patch: PenMeshPatch, width: Double, height: Double) -> Subdivision {
        let geometry = Self.geometryBounds(patch, width: width, height: height)
        let color = Self.colorBounds(patch)
        return Subdivision(
            u: max(cells(geometry.uu + geometry.uv, geometricTolerance), cells(color.uu + color.uv, colorTolerance)),
            v: max(cells(geometry.vv + geometry.uv, geometricTolerance), cells(color.vv + color.uv, colorTolerance))
        )
    }

    /// The cell count along one axis that keeps that axis's half of the error bound,
    /// `⅛ M h²`, within half the tolerance: `h ≤ √(4 tol / M)`.
    private func cells(_ curvature: Double, _ tolerance: Double) -> Int {
        guard curvature > 0 else { return 1 }
        let needed = (curvature / (4 * tolerance)).squareRoot().rounded(.up)
        guard needed.isFinite, needed < Double(maximumSubdivisions) else { return maximumSubdivisions }
        return max(Int(needed), 1)
    }

    /// Bounds on the second derivatives of one patch quantity over the whole patch.
    private struct Curvature {
        var uu = 0.0
        var vv = 0.0
        var uv = 0.0
    }

    /// Bounds on the position's second derivatives, in device pixels, from the control
    /// net's second differences (the convex-hull property of the derivative patches).
    private static func geometryBounds(_ patch: PenMeshPatch, width: Double, height: Double) -> Curvature {
        let net = patch.controlPoints.map { SIMD2($0.x * width, $0.y * height) }
        func point(_ row: Int, _ column: Int) -> SIMD2<Double> {
            net[row * 4 + column]
        }
        func length(_ vector: SIMD2<Double>) -> Double {
            (vector * vector).sum().squareRoot()
        }
        var result = Curvature()
        for a in 0 ..< 4 {
            for b in 0 ..< 2 {
                result.uu = max(result.uu, 6 * length(point(a, b + 2) - 2 * point(a, b + 1) + point(a, b)))
                result.vv = max(result.vv, 6 * length(point(b + 2, a) - 2 * point(b + 1, a) + point(b, a)))
            }
        }
        for row in 0 ..< 3 {
            for column in 0 ..< 3 {
                let twist = point(row + 1, column + 1) - point(row + 1, column) - point(row, column + 1) + point(row, column)
                result.uv = max(result.uv, 9 * length(twist))
            }
        }
        return result
    }

    /// Bounds on the second derivatives of each premultiplied channel, `c × α`.
    ///
    /// Each channel is bilinear in the eased parameters `s = S(u)`, `t = S(v)`, with
    /// `|S′| ≤ 3/2` and `|S″| ≤ 6`, so for a bilinear `g` with corner differences `Gₛ`,
    /// `Gₜ` and twist `Gₛₜ`: `|gᵤ| ≤ 1.5 Gₛ`, `|gᵤᵤ| ≤ 6 Gₛ`, `|gᵤᵥ| ≤ 2.25 Gₛₜ`. The
    /// product rule combines color and alpha, both bounded by 1.
    private static func colorBounds(_ patch: PenMeshPatch) -> Curvature {
        let corners = [patch.topLeftColor, patch.topRightColor, patch.bottomLeftColor, patch.bottomRightColor]
        let alpha = Differences(corners.map(\.alpha))
        var result = Curvature()
        for channel in [\PenMeshColor.red, \.green, \.blue] {
            let color = Differences(corners.map { $0[keyPath: channel] })
            result.uu = max(result.uu, 6 * color.s + 4.5 * color.s * alpha.s + 6 * alpha.s)
            result.vv = max(result.vv, 6 * color.t + 4.5 * color.t * alpha.t + 6 * alpha.t)
            result.uv = max(result.uv, 2.25 * (color.st + color.s * alpha.t + color.t * alpha.s + alpha.st))
        }
        return result
    }

    /// The largest corner differences of one bilinear channel.
    private struct Differences {
        /// Corners in the order top-left, top-right, bottom-left, bottom-right.
        init(_ corners: [Double]) {
            s = max(abs(corners[1] - corners[0]), abs(corners[3] - corners[2]))
            t = max(abs(corners[2] - corners[0]), abs(corners[3] - corners[1]))
            st = abs(corners[0] - corners[1] - corners[2] + corners[3])
        }

        let s: Double
        let t: Double
        let st: Double
    }
}
