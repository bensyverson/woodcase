//
//  PenFill+GradientFrame.swift
//  Woodcase
//

import CoreGraphics

extension PenFill.PenGradientFill {
    /// The map from the gradient's own unit space into user space, for a node whose box is `bounds`.
    ///
    /// Pen lays out every gradient type in the node's *normalised* box, the unit square
    /// that is then stretched to the box — established from its renders
    /// (`project/2026-09-26-gradient-geometry-and-per-side-strokes.md`). In the
    /// gradient's own space the gradient is centred on the origin with unit extent:
    ///
    /// - a **linear** gradient runs from stop 0 at `(0, 0.5)` to stop 1 at `(0, -0.5)`,
    ///   bottom to top (y grows downward);
    /// - a **radial** gradient runs from the origin to the circle of radius 0.5;
    /// - an **angular** gradient starts pointing up, `(0, -1)`, and sweeps clockwise on screen.
    ///
    /// That space is scaled by `size` (width along its x axis, height along its y axis;
    /// default 1), turned counter-clockwise on screen by `rotation` degrees, moved to
    /// `center` (a fraction of the box; default the middle), and only then stretched to
    /// `bounds`. So on a box that is not square, a 45° gradient does not run at 45°, and
    /// a radial or angular gradient is an ellipse, exactly as in Pen.
    ///
    /// Built on ``GradientGeometry``'s CG-free map (``GradientGeometry/affineComponents``)
    /// so the renderer and the code emitters share one computation of the gradient's scale,
    /// rotation and centre; this adds only the final stretch from the normalised box to
    /// `bounds`.
    ///
    /// - Parameter bounds: The node's box in user space: the domain the paint is laid out over.
    /// - Returns: The transform to concatenate before drawing in gradient space.
    func frameTransform(in bounds: CGRect) -> CGAffineTransform {
        let m = GradientGeometry(self).affineComponents
        let toBox = CGAffineTransform(
            a: CGFloat(m.a), b: CGFloat(m.b), c: CGFloat(m.c),
            d: CGFloat(m.d), tx: CGFloat(m.tx), ty: CGFloat(m.ty)
        )
        return toBox
            .concatenating(CGAffineTransform(scaleX: bounds.width, y: bounds.height))
            .concatenating(CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }
}
