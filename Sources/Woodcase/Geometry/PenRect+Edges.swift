import Foundation

extension PenRect {
    /// The same rectangle with a non-negative width and height, moved so it covers the
    /// same area — how CoreGraphics reads every rect it is given.
    var standardized: PenRect {
        PenRect(
            x: min(x, x + width),
            y: min(y, y + height),
            width: abs(width),
            height: abs(height)
        )
    }

    /// The horizontal centre.
    var midX: Double {
        x + width / 2
    }

    /// The vertical centre.
    var midY: Double {
        y + height / 2
    }

    /// The right edge.
    var maxX: Double {
        x + width
    }

    /// The bottom edge.
    var maxY: Double {
        y + height
    }

    /// The rectangle moved in by `dx` on the left and right and by `dy` on the top and bottom.
    func insetBy(dx: Double, dy: Double) -> PenRect {
        PenRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }
}
