//
//  PenLayoutEngine+PlaneTransform.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// An affine map of the plane, `(x, y) ↦ (a·x + c·y + tx, b·x + d·y + ty)`, in the
    /// y-down layout space — the same convention as `CGAffineTransform`.
    ///
    /// ``PenPlacement`` pairs one with the box it carries. Foundation-only, so
    /// ``absoluteRects(under:in:layoutRects:)`` and
    /// ``canvasTransform(of:in:layoutRects:)`` compose turned ancestors on every platform
    /// the library builds for; ``cgAffineTransform`` converts it where Core Graphics exists.
    struct PlaneTransform: Friendly {
        /// The x-axis column's x.
        public var a = 1.0
        /// The x-axis column's y.
        public var b = 0.0
        /// The y-axis column's x.
        public var c = 0.0
        /// The y-axis column's y.
        public var d = 1.0
        /// The translation's x.
        public var tx = 0.0
        /// The translation's y.
        public var ty = 0.0

        /// Creates a map from its six coefficients; the defaults are the identity's.
        ///
        /// - Parameters:
        ///   - a: The x-axis column's x.
        ///   - b: The x-axis column's y.
        ///   - c: The y-axis column's x.
        ///   - d: The y-axis column's y.
        ///   - tx: The translation's x.
        ///   - ty: The translation's y.
        public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.tx = tx
            self.ty = ty
        }

        /// The identity.
        public static let identity = PlaneTransform()

        /// A translation by `(x, y)`.
        public static func translation(x: Double, y: Double) -> PlaneTransform {
            PlaneTransform(tx: x, ty: y)
        }

        /// Where a node's own coordinates land in its parent's: the node's box drawn
        /// centred in its layout rect, flipped, then turned by Pen's counter-clockwise
        /// degrees, about that centre — the renderer's placement (`PenRenderer.enter`).
        ///
        /// - Parameters:
        ///   - node: The node, for its rotation and flips.
        ///   - rect: Its layout rect, in its parent's space.
        ///   - box: Its unturned box, in its own coordinates.
        static func placing(_ node: PenNode, rect: PenRect, box: PenRect) -> PlaneTransform {
            let rotation = node.common.rotation?.literalValue ?? 0
            let signX = node.common.flipX?.literalValue == true ? -1.0 : 1.0
            let signY = node.common.flipY?.literalValue == true ? -1.0 : 1.0
            guard rotation != 0 || signX < 0 || signY < 0 else {
                return translation(x: rect.x - box.x, y: rect.y - box.y)
            }
            let radians = -rotation * .pi / 180
            let cosine = cos(radians), sine = sin(radians)
            let turn = PlaneTransform(a: cosine * signX, b: sine * signX, c: -sine * signY, d: cosine * signY)
            return translation(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                .concatenating(turn)
                .concatenating(translation(x: -(box.x + box.width / 2), y: -(box.y + box.height / 2)))
        }

        /// This map after `inner`: a point goes through `inner` first.
        public func concatenating(_ inner: PlaneTransform) -> PlaneTransform {
            PlaneTransform(
                a: a * inner.a + c * inner.b,
                b: b * inner.a + d * inner.b,
                c: a * inner.c + c * inner.d,
                d: b * inner.c + d * inner.d,
                tx: a * inner.tx + c * inner.ty + tx,
                ty: b * inner.tx + d * inner.ty + ty
            )
        }

        /// Where this map sends a point.
        ///
        /// - Parameter point: The point, in the map's source coordinates.
        /// - Returns: The point, in its destination coordinates.
        public func apply(to point: PenPoint) -> PenPoint {
            PenPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
        }

        /// The map that undoes this one, or `nil` when this one is singular — it
        /// collapses the plane onto a line or a point, as a zero scale would.
        public func inverted() -> PlaneTransform? {
            let determinant = a * d - b * c
            guard determinant != 0, determinant.isFinite else { return nil }
            let ia = d / determinant, ib = -b / determinant
            let ic = -c / determinant, id = a / determinant
            return PlaneTransform(
                a: ia, b: ib, c: ic, d: id,
                tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty)
            )
        }

        /// The axis-aligned bounds of `rect` mapped.
        ///
        /// - Parameter rect: A rect in the map's source coordinates; its
        ///   ``PenRect/unturnedSize`` plays no part.
        /// - Returns: The bounds of its four corners mapped.
        public func bounds(of rect: PenRect) -> PenRect {
            if b == 0, c == 0, a == 1, d == 1 {
                return PenRect(x: rect.x + tx, y: rect.y + ty, width: rect.width, height: rect.height)
            }
            var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
            for x in [rect.x, rect.x + rect.width] {
                for y in [rect.y, rect.y + rect.height] {
                    let mappedX = a * x + c * y + tx
                    let mappedY = b * x + d * y + ty
                    minX = min(minX, mappedX)
                    maxX = max(maxX, mappedX)
                    minY = min(minY, mappedY)
                    maxY = max(maxY, mappedY)
                }
            }
            return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}
