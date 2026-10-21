//
//  FigmaGradientGeometry.swift
//  Woodcase
//

import Foundation

/// A Figma gradient transform as Pen's gradient frame: a center, a size and a turn in the
/// node's normalized box.
///
/// Figma's `transform` maps the normalized box into gradient space, where a linear gradient
/// runs from `(0, 0.5)` to `(1, 0.5)`, a radial one fills the circle of radius 0.5 about
/// `(0.5, 0.5)`, and an angular one starts along +x from that center and sweeps clockwise
/// (its SVG export writes `conic-gradient(from 90deg, …)`). Pen's gradient space
/// (``PenFill/PenGradientFill/frameTransform(in:)``) is centered on the origin, a linear
/// gradient running from `(0, 0.5)` up to `(0, -0.5)` and an angular one starting up. The
/// map from Pen's space to Figma's is the quarter turn `(x, y) ↦ (0.5 − y, 0.5 + x)`, so
/// Pen's frame is the inverse of Figma's transform after that turn, decomposed as Pen
/// writes it: translate to the center, turn, scale. Pen's frame has no skew; one is dropped
/// with the gradient's own axis — Pen's y, along which a linear gradient runs — kept exact.
struct FigmaGradientGeometry: Friendly {
    /// The center's x, as a fraction of the box's width.
    var centerX: Double
    /// The center's y, as a fraction of the box's height.
    var centerY: Double
    /// The extent across the gradient, as a fraction of the box.
    var width: Double
    /// The extent along the gradient: a linear gradient's length, as a fraction of the box.
    var height: Double
    /// Pen's counter-clockwise degrees.
    var rotation: Double
    /// Whether Figma's transform skews the gradient, which Pen's frame leaves out.
    var isSkewed: Bool

    /// The Pen frame of a Figma gradient `transform`, or `nil` when it is singular.
    init?(figma transform: FigmaTransform) {
        guard let inverse = transform.inverted else { return nil }
        // Pen's x axis is Figma's +y, its y axis Figma's −x; both through the box's map.
        let axisX = inverse.applyLinear(x: 0, y: 1)
        let axisY = inverse.applyLinear(x: -1, y: 0)
        let center = inverse.apply(x: 0.5, y: 0.5)
        let height = hypot(axisY.x, axisY.y)
        guard height > 0 else { return nil }
        // Pen's y column is height·(sin θ, cos θ), its x column width·(cos θ, −sin θ).
        let sine = axisY.x / height, cosine = axisY.y / height
        let width = axisX.x * cosine - axisX.y * sine
        let residual = hypot(axisX.x - width * cosine, axisX.y + width * sine)
        centerX = Self.snapped(center.x)
        centerY = Self.snapped(center.y)
        self.width = Self.snapped(width)
        self.height = Self.snapped(height)
        rotation = Self.snapped(atan2(sine, cosine) * 180 / .pi)
        isSkewed = residual > FigmaTransform.tolerance * max(1, abs(width))
    }

    /// `value` with float noise below a billionth rounded away, so an untouched gradient
    /// writes `0.5`, not `0.49999999999`.
    private static func snapped(_ value: Double) -> Double {
        let rounded = (value * 1e9).rounded() / 1e9
        return rounded == 0 ? 0 : rounded
    }
}
