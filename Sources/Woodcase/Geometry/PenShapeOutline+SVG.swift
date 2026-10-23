import Foundation

extension PenShapeOutline {
    /// The outline as SVG path data: every element written as the absolute SVG commands
    /// that trace what the CoreGraphics call of the same name draws, so an SVG emitter
    /// draws the outline the renderer does.
    ///
    /// An elliptical arc becomes an SVG `A` command between its end points — the ellipse
    /// is axis-aligned and both points lie on it, so the radii and the two flags pick out
    /// exactly the arc CoreGraphics draws. A whole ellipse is two half arcs, a rounded
    /// rect four edges and four corner arcs, and a tangent arc its straight lead-in and
    /// a circular arc between the tangent points.
    ///
    /// - Parameter number: How a coordinate is written, e.g. at a fixed precision.
    /// - Returns: The commands separated by spaces, e.g. `M0 0 L10 0 Z`.
    func svgPathData(number: (Double) -> String) -> String {
        withoutActuallyEscaping(number) { number in
            var writer = PenSVGPathWriter(number: number)
            for element in elements {
                writer.write(element)
            }
            return writer.pathData
        }
    }
}
