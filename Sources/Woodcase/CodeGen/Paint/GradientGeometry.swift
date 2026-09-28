//
//  GradientGeometry.swift
//  Woodcase
//

import Foundation

/// A gradient fill's geometry in the node's normalised box: Pen's one map from the
/// gradient's own unit space into that box, with the defaults filled in.
///
/// In its own space a gradient is centred on the origin with unit extent (y down): a
/// linear gradient runs from stop 0 at `(0, 0.5)` to stop 1 at `(0, −0.5)`, bottom to
/// top; a radial one from the origin to the circle of radius ½. That space is scaled by
/// ``width`` and ``height``, turned counter-clockwise on screen by ``rotation`` degrees
/// and moved to ``center`` (`project/2026-09-26-gradient-geometry-and-per-side-strokes.md`).
/// The renderer's `PenFill.PenGradientFill.frameTransform(in:)` builds its
/// `CGAffineTransform` from ``affineComponents`` and adds only the final stretch to the
/// node's box, so this is the one computation of a gradient's scale, rotation and centre —
/// not a CG-free copy of it. Without CoreGraphics, a code emitter can also state the map in
/// its target's own terms: CSS as an angle (the map's rotation, which is all a
/// `linear-gradient` can carry) and a radial ellipse, SwiftUI as start and end points
/// (``linearStart``, ``linearEnd``).
struct GradientGeometry: Friendly {
    /// The gradient's centre in the normalised box; the middle by default.
    var center: NormalizedPoint

    /// The scale along the gradient's own x axis; 1 by default.
    var width: Double

    /// The scale along the gradient's own y axis; 1 by default.
    var height: Double

    /// The turn, in degrees counter-clockwise on screen; 0 by default.
    var rotation: Double

    /// Reads the geometry of `gradient`, filling in Pen's defaults.
    init(_ gradient: PenFill.PenGradientFill) {
        center = NormalizedPoint(x: gradient.center?.x ?? 0.5, y: gradient.center?.y ?? 0.5)
        width = gradient.size?.width?.literalValue ?? 1
        height = gradient.size?.height?.literalValue ?? 1
        rotation = gradient.rotation?.literalValue ?? 0
    }

    /// The map from the gradient's own unit space into the normalised box, as the six
    /// numbers of a row-vector affine matrix: `x′ = a·x + c·y + tx`, `y′ = b·x + d·y + ty`
    /// — the same layout `CGAffineTransform`'s own six-argument initializer takes, so a
    /// caller that does have CoreGraphics builds one directly from this. This is the one
    /// place the gradient's scale and rotation are computed; ``point(_:)`` and the
    /// renderer's `frameTransform(in:)` both go through it.
    var affineComponents: (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        let radians = rotation * .pi / 180
        // Counter-clockwise on a y-down screen is a rotation by −θ in these coordinates.
        let cosine = cos(radians)
        let sine = sin(radians)
        return (a: width * cosine, b: -width * sine, c: height * sine, d: height * cosine, tx: center.x, ty: center.y)
    }

    /// Where a point of the gradient's own space lands in the normalised box.
    func point(_ local: NormalizedPoint) -> NormalizedPoint {
        let m = affineComponents
        return NormalizedPoint(x: m.a * local.x + m.c * local.y + m.tx, y: m.b * local.x + m.d * local.y + m.ty)
    }

    /// Where a linear gradient's stop 0 lies.
    var linearStart: NormalizedPoint {
        point(NormalizedPoint(x: 0, y: 0.5))
    }

    /// Where a linear gradient's stop 1 lies.
    var linearEnd: NormalizedPoint {
        point(NormalizedPoint(x: 0, y: -0.5))
    }

    /// A radial gradient's horizontal radius, as a fraction of the box's width, before
    /// any rotation.
    var radiusX: Double {
        width / 2
    }

    /// A radial gradient's vertical radius, as a fraction of the box's height, before
    /// any rotation.
    var radiusY: Double {
        height / 2
    }

    /// Whether a radial gradient's ellipse is the default one, centred and touching the
    /// box's sides.
    var isDefaultEllipse: Bool {
        radiusX == 0.5 && radiusY == 0.5 && center == .center
    }
}
