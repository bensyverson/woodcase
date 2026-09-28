//
//  PenRect+PixelSnapping.swift
//  Woodcase
//

import Foundation

public extension PenRect {
    /// The rect at the same origin, grown to a whole number of pixels at `scale` — how Pen
    /// sizes a raster export of a painted extent: it keeps the extent's corner, fractional
    /// or not, and rounds the pixel size up. Pen's 2x export of a node whose painted extent
    /// is 149.39×134.75 pt is 299×270 px, drawn from the extent's exact corner
    /// (`PenPaintedExtentProbeTests`; `project/2026-09-28-geometry-model.md`).
    ///
    /// A size within a millionth of a pixel of a whole number is taken as that number, so
    /// floating-point noise never adds a pixel.
    ///
    /// - Parameter scale: Pixels per point; a scale that is not positive leaves the rect
    ///   as it is.
    /// - Returns: The grown rect, in points, without an ``unturnedSize``.
    func grownToWholePixels(at scale: Double) -> PenRect {
        guard scale > 0, scale.isFinite else { return bounds }
        let tolerance = 1e-6
        let pixelWidth = Swift.max(0, (width * scale - tolerance).rounded(.up))
        let pixelHeight = Swift.max(0, (height * scale - tolerance).rounded(.up))
        return PenRect(x: x, y: y, width: pixelWidth / scale, height: pixelHeight / scale)
    }
}
