//
//  FigmaTransform.swift
//  Woodcase
//

import Foundation

/// A Figma `Matrix`: the affine map `(x, y) ↦ (m00·x + m01·y + m02, m10·x + m11·y + m12)`,
/// y down — a node's transform into its parent, or a paint's.
struct FigmaTransform: Friendly {
    /// The x-axis column's x.
    var m00: Double
    /// The y-axis column's x.
    var m01: Double
    /// The translation's x.
    var m02: Double
    /// The x-axis column's y.
    var m10: Double
    /// The y-axis column's y.
    var m11: Double
    /// The translation's y.
    var m12: Double

    /// Where a Pen node with this transform sits, in Pen's own terms.
    ///
    /// Pen places a node by its top-left anchor, flips it, then turns it counter-clockwise
    /// about that anchor (``PenLayoutEngine/freeRect(of:x:y:box:)``) — the same anchor
    /// Figma's matrix turns about. So a matrix with orthonormal columns decomposes exactly.
    struct Placement: Friendly {
        /// The anchor's x, in the parent's coordinates.
        var x: Double
        /// The anchor's y.
        var y: Double
        /// Pen's counter-clockwise degrees.
        var rotation: Double
        /// Whether the node is mirrored left to right.
        var flipX: Bool
        /// Whether the node is mirrored top to bottom.
        var flipY: Bool
        /// Whether the matrix scales or skews: the placement keeps its turn and mirror and
        /// leaves the rest out.
        var isSkewed: Bool
    }

    /// The identity.
    static let identity = FigmaTransform(m00: 1, m01: 0, m02: 0, m10: 0, m11: 1, m12: 0)

    /// How far a column may stray from unit length and from square before the matrix
    /// counts as scaled or skewed. Figma stores `float`s, so a turned matrix is off by
    /// about 1e-7.
    static let tolerance = 1e-5

    /// Reads a `Matrix` struct, or `nil` when `value` is not one.
    init?(_ value: KiwiValue?) {
        guard let value, value.recordValue != nil else { return nil }
        func entry(_ key: String) -> Double {
            value[key]?.doubleValue ?? 0
        }
        self.init(m00: entry("m00"), m01: entry("m01"), m02: entry("m02"), m10: entry("m10"), m11: entry("m11"), m12: entry("m12"))
    }

    /// A matrix of these entries.
    init(m00: Double, m01: Double, m02: Double, m10: Double, m11: Double, m12: Double) {
        self.m00 = m00
        self.m01 = m01
        self.m02 = m02
        self.m10 = m10
        self.m11 = m11
        self.m12 = m12
    }

    /// The transform as Pen's position, turn and flips.
    ///
    /// A mirror with no turn could be a flip about either axis plus a half turn; the
    /// decomposition takes whichever leaves the smaller turn, so Figma's vertical flip is
    /// Pen's `flipY`, not `flipX` and 180°.
    var placement: Placement {
        let determinant = m00 * m11 - m01 * m10
        let isMirrored = determinant < 0
        // Pen's matrix is R(θ)·diag(sx, sy), θ = −rotation: column 0 is sx·(cos θ, sin θ).
        var flipX = isMirrored, flipY = false
        var theta = atan2(m10 * (flipX ? -1 : 1), m00 * (flipX ? -1 : 1))
        if isMirrored {
            // The same matrix as a vertical flip turns by θ + π.
            let alternative = atan2(m10, m00)
            if abs(alternative) < abs(theta) {
                theta = alternative
                flipX = false
                flipY = true
            }
        }
        let lengthX = hypot(m00, m10), lengthY = hypot(m01, m11)
        let dot = m00 * m01 + m10 * m11
        let isSkewed = abs(lengthX - 1) > Self.tolerance || abs(lengthY - 1) > Self.tolerance || abs(dot) > Self.tolerance
        var rotation = -theta * 180 / .pi
        if abs(rotation) < 1e-9 { rotation = 0 }
        return Placement(x: m02, y: m12, rotation: rotation, flipX: flipX, flipY: flipY, isSkewed: isSkewed)
    }

    /// The map that undoes this one, or `nil` when it collapses the plane.
    var inverted: FigmaTransform? {
        let determinant = m00 * m11 - m01 * m10
        guard determinant != 0, determinant.isFinite else { return nil }
        let a = m11 / determinant, b = -m01 / determinant
        let c = -m10 / determinant, d = m00 / determinant
        return FigmaTransform(m00: a, m01: b, m02: -(a * m02 + b * m12), m10: c, m11: d, m12: -(c * m02 + d * m12))
    }

    /// Where the map sends `(x, y)`.
    func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        (m00 * x + m01 * y + m02, m10 * x + m11 * y + m12)
    }

    /// Where the map's linear part sends the offset `(x, y)`.
    func applyLinear(x: Double, y: Double) -> (x: Double, y: Double) {
        (m00 * x + m01 * y, m10 * x + m11 * y)
    }

    /// Whether this is the identity, within ``tolerance``.
    var isIdentity: Bool {
        [m00 - 1, m01, m02, m10, m11 - 1, m12].allSatisfy { abs($0) <= Self.tolerance }
    }
}
