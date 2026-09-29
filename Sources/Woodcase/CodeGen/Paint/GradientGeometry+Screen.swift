//
//  GradientGeometry+Screen.swift
//  Woodcase
//

import Foundation

extension GradientGeometry {
    /// A linear gradient's stop position as an affine function of a point in the
    /// normalized box: `position = du·x + dv·y + offset`.
    ///
    /// Pen's stop position is `½ − y` in the gradient's own space (stop 0 at `y = ½`, stop 1
    /// at `y = −½`), so it is constant along the gradient's own x axis — the ramp's
    /// isolines — and an emitter that cannot state Pen's map directly (CSS) can place its
    /// own ramp by matching this function.
    struct LinearRamp: Friendly {
        /// How far the position moves per unit of the box's width.
        var du: Double
        /// How far the position moves per unit of the box's height.
        var dv: Double
        /// The position at the box's top-left corner.
        var offset: Double

        /// The stop position at `point` of the normalized box; below 0 and above 1 lie the
        /// padded ends.
        func position(at point: NormalizedPoint) -> Double {
            du * point.x + dv * point.y + offset
        }
    }

    /// The linear gradient's ramp over the normalized box, or `nil` when the map collapses
    /// (a zero `size`), where Pen draws nothing.
    var linearRamp: LinearRamp? {
        let m = affineComponents
        let determinant = m.a * m.d - m.b * m.c
        guard abs(determinant) > 1e-12 else { return nil }
        // The gradient's own y is the second row of the inverse map, applied to the offset from the center.
        let du = m.b / determinant
        let dv = -m.a / determinant
        return LinearRamp(du: du, dv: dv, offset: 0.5 - du * m.tx - dv * m.ty)
    }

    /// The on-screen bearing, in degrees clockwise from straight up in `[0, 360)`, of the
    /// ray from the gradient's center along which an angular gradient reaches `turn` (0…1)
    /// on a `width` × `height` box.
    ///
    /// Pen measures an angular gradient's turn clockwise from up in the gradient's own
    /// space, before the stretch to the box; on a box that is not square the stretch bends
    /// the bearings, so equal turns no longer sweep equal angles on screen.
    func angularBearing(atTurn turn: Double, width: Double, height: Double) -> Double {
        let m = affineComponents
        let radians = turn * 2 * .pi
        // Clockwise from up in y-down space.
        let x = sin(radians)
        let y = -cos(radians)
        let dx = width * (m.a * x + m.c * y)
        let dy = height * (m.b * x + m.d * y)
        var degrees = (atan2(dy, dx) * 180 / .pi + 90).truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return degrees > 360 - 1e-9 ? 0 : degrees
    }

    /// Whether the map onto a `width` × `height` box keeps angles and handedness — a turn,
    /// a uniform scale and a move — so an angular gradient's turns are its bearings, offset
    /// by ``angularBearing(atTurn:width:height:)`` at turn 0.
    func keepsAngles(width: Double, height: Double) -> Bool {
        let m = affineComponents
        let column1 = (x: width * m.a, y: height * m.b)
        let column2 = (x: width * m.c, y: height * m.d)
        let length1 = column1.x * column1.x + column1.y * column1.y
        let length2 = column2.x * column2.x + column2.y * column2.y
        let tolerance = 1e-9 * max(length1, length2)
        let dot = column1.x * column2.x + column1.y * column2.y
        let determinant = column1.x * column2.y - column1.y * column2.x
        return abs(length1 - length2) <= tolerance && abs(dot) <= tolerance && determinant > 0
    }

    /// A radial gradient's radii, as fractions of the box's width and height, when its
    /// ellipse keeps to the box's axes — unturned, turned a quarter (the radii swap), or a
    /// circle in the normalized box, which a turn does not change — else `nil`.
    var axisAlignedRadii: (x: Double, y: Double)? {
        let radians = rotation * .pi / 180
        if abs(abs(width) - abs(height)) < 1e-12 || abs(sin(radians)) < 1e-9 {
            return (abs(width) / 2, abs(height) / 2)
        }
        if abs(cos(radians)) < 1e-9 {
            return (abs(height) / 2, abs(width) / 2)
        }
        return nil
    }
}
