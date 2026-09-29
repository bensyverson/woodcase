//
//  PenMeshPatch.swift
//  Woodcase
//

import Foundation

/// One cell of a mesh gradient: a bicubic tensor-product Bézier patch whose color is a
/// smoothstep-eased bilinear blend of its four corner colors.
///
/// Parameters run `u` left to right and `v` top to bottom, each over `0...1`. The
/// geometry is `B(v; B(u; row₀), …, B(u; row₃))` over the 4×4 ``controlPoints``, built
/// from the corners' positions and handles:
///
/// ```
/// row 0:  TL            TL+TL.right              TR+TR.left              TR
/// row 1:  TL+TL.bottom  TL+TL.right+TL.bottom    TR+TR.left+TR.bottom    TR+TR.bottom
/// row 2:  BL+BL.top     BL+BL.right+BL.top       BR+BR.left+BR.top       BR+BR.top
/// row 3:  BL            BL+BL.right              BR+BR.left              BR
/// ```
///
/// The four interior points take the zero-twist (parallelogram) rule. The color follows
/// the *parameters*, not the position: moving a point warps the color field with it.
/// Both rules are what Pen's exports show; `project/2026-09-26-mesh-gradients.md` §1.
public struct PenMeshPatch: Friendly {
    /// Creates the patch spanned by four neighboring grid vertices.
    ///
    /// - Parameters:
    ///   - topLeft: The corner at `(u, v) = (0, 0)`.
    ///   - topRight: The corner at `(1, 0)`.
    ///   - bottomLeft: The corner at `(0, 1)`.
    ///   - bottomRight: The corner at `(1, 1)`.
    public init(
        topLeft: PenMeshGrid.Vertex,
        topRight: PenMeshGrid.Vertex,
        bottomLeft: PenMeshGrid.Vertex,
        bottomRight: PenMeshGrid.Vertex
    ) {
        func offset(_ point: PenMeshPoint.Vector, _ deltas: PenMeshPoint.Vector...) -> PenMeshPoint.Vector {
            deltas.reduce(point) { PenMeshPoint.Vector($0.x + $1.x, $0.y + $1.y) }
        }
        let tl = topLeft.position, tr = topRight.position, bl = bottomLeft.position, br = bottomRight.position
        let tlh = topLeft.handles, trh = topRight.handles, blh = bottomLeft.handles, brh = bottomRight.handles
        controlPoints = [
            tl, offset(tl, tlh.right), offset(tr, trh.left), tr,
            offset(tl, tlh.bottom), offset(tl, tlh.right, tlh.bottom), offset(tr, trh.left, trh.bottom), offset(tr, trh.bottom),
            offset(bl, blh.top), offset(bl, blh.right, blh.top), offset(br, brh.left, brh.top), offset(br, brh.top),
            bl, offset(bl, blh.right), offset(br, brh.left), br,
        ]
        topLeftColor = topLeft.color
        topRightColor = topRight.color
        bottomLeftColor = bottomLeft.color
        bottomRightColor = bottomRight.color
    }

    /// The 16 Bézier control points in unit space, row-major: index `row * 4 + column`,
    /// where the row follows `v` and the column follows `u`.
    public let controlPoints: [PenMeshPoint.Vector]

    /// The color at `(u, v) = (0, 0)`.
    public let topLeftColor: PenMeshColor

    /// The color at `(1, 0)`.
    public let topRightColor: PenMeshColor

    /// The color at `(0, 1)`.
    public let bottomLeftColor: PenMeshColor

    /// The color at `(1, 1)`.
    public let bottomRightColor: PenMeshColor

    /// The point on the patch at the given parameters, in the node's unit space.
    ///
    /// - Parameters:
    ///   - u: The horizontal parameter, `0...1`.
    ///   - v: The vertical parameter, `0...1`.
    /// - Returns: The evaluated position.
    public func position(u: Double, v: Double) -> PenMeshPoint.Vector {
        let bu = Self.bernstein(u)
        let bv = Self.bernstein(v)
        var x = 0.0
        var y = 0.0
        for row in 0 ..< 4 {
            var rowX = 0.0
            var rowY = 0.0
            for column in 0 ..< 4 {
                let point = controlPoints[row * 4 + column]
                rowX += bu[column] * point.x
                rowY += bu[column] * point.y
            }
            x += bv[row] * rowX
            y += bv[row] * rowY
        }
        return PenMeshPoint.Vector(x, y)
    }

    /// The four cubic Bernstein weights at `t`. At `t = 0` and `t = 1` they are exactly
    /// `(1, 0, 0, 0)` and `(0, 0, 0, 1)`, so a patch edge evaluates to the same bits from
    /// either neighboring patch.
    static func bernstein(_ t: Double) -> [Double] {
        let s = 1 - t
        return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t]
    }

    /// The color at the given parameters: the corners blended bilinearly by
    /// ``ease(_:)`` of each parameter, on unpremultiplied sRGB-encoded channels.
    ///
    /// - Parameters:
    ///   - u: The horizontal parameter, `0...1`.
    ///   - v: The vertical parameter, `0...1`.
    /// - Returns: The blended color.
    public func color(u: Double, v: Double) -> PenMeshColor {
        let s = Self.ease(u)
        let t = Self.ease(v)
        /// Nested linear interpolation, not four weights: a channel equal at all four
        /// corners comes out bit-for-bit equal, so a uniform translucent mesh stays uniform.
        func blend(_ channel: KeyPath<PenMeshColor, Double>) -> Double {
            let top = topLeftColor[keyPath: channel] + s * (topRightColor[keyPath: channel] - topLeftColor[keyPath: channel])
            let bottom = bottomLeftColor[keyPath: channel] + s * (bottomRightColor[keyPath: channel] - bottomLeftColor[keyPath: channel])
            return top + t * (bottom - top)
        }
        return PenMeshColor(red: blend(\.red), green: blend(\.green), blue: blend(\.blue), alpha: blend(\.alpha))
    }

    /// Smoothstep, `t²(3 − 2t)`: the easing that gives a mesh its soft look, with zero
    /// slope at every vertex.
    ///
    /// - Parameter t: A parameter in `0...1`.
    /// - Returns: The eased parameter.
    public static func ease(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }
}
