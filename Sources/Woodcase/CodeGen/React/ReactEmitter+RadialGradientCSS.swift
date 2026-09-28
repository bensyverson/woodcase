//
//  ReactEmitter+RadialGradientCSS.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// A radial gradient at Pen's geometry.
    ///
    /// Pen's radial gradient reaches radius ½ of its `size` in the normalised box, around
    /// `center`, turned by `rotation`. While that ellipse keeps to the box's axes
    /// (``GradientGeometry/axisAlignedRadii``) it is a CSS `radial-gradient` ellipse —
    /// `closest-side` for the default one. A CSS ellipse cannot turn, so a turned one is an
    /// SVG paint server in the normalised box, stretched over it
    /// (``svgRadialGradient(_:stops:box:outsets:)``); an SVG image cannot read the page's
    /// custom properties, so a turned ellipse with a variable colour keeps the unturned CSS
    /// ellipse.
    static func cssRadialGradient(
        _ geometry: GradientGeometry,
        stops: GradientStops,
        box: FillBox,
        outsets: EdgeLengths
    ) -> CSSGradient {
        let radii = geometry.axisAlignedRadii
        if radii == nil, let svg = svgRadialGradient(geometry, stops: stops, box: box, outsets: outsets) {
            return svg
        }
        let (radiusX, radiusY) = radii ?? (geometry.radiusX, geometry.radiusY)
        let list = stops.map { "\($0.color) \(cssPercent($0.position))" }.joined(separator: ", ")
        let at = gradientCentre(geometry.center, outsets: outsets)
        let shape: String
        if outsets.isZero {
            shape = radiusX == 0.5 && radiusY == 0.5 && at.isEmpty
                ? "closest-side"
                : "\(cssPercent(radiusX)) \(cssPercent(radiusY))\(at.isEmpty ? " at 50% 50%" : at)"
        } else {
            let horizontal = outsets.left + outsets.right
            let vertical = outsets.top + outsets.bottom
            shape = "\(fraction(of: horizontal, radiusX)) \(fraction(of: vertical, radiusY))\(at)"
        }
        return CSSGradient(image: "radial-gradient(\(shape), \(list))")
    }

    /// A turned radial gradient as an SVG image: the normalised box as its view box,
    /// stretched to the tile with `preserveAspectRatio="none"`, and Pen's map as the
    /// gradient's transform — or `nil` when a stop's colour is not a hex literal an SVG
    /// image can carry.
    private static func svgRadialGradient(
        _ geometry: GradientGeometry,
        stops: GradientStops,
        box: FillBox,
        outsets: EdgeLengths
    ) -> CSSGradient? {
        var stopElements: [String] = []
        for stop in stops {
            guard let channels = hexChannels(stop.color) else { return nil }
            let color = "#" + channels.prefix(3).map { hexByte($0) }.joined()
            let opacity = channels[3] == 255 ? "" : " stop-opacity=\"\(cssNumber(Double(channels[3]) / 255, decimals: 4))\""
            stopElements.append("<stop offset=\"\(cssNumber(stop.position))\" stop-color=\"\(color)\"\(opacity)/>")
        }
        let growth = tileGrowth(box: box, outsets: outsets)
        let origin = cssNumber(-(growth - 1) / 2)
        let extent = cssNumber(growth)
        let m = geometry.affineComponents
        let matrix = [m.a, m.b, m.c, m.d, m.tx, m.ty].map { cssNumber($0) }.joined(separator: " ")
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(origin) \(origin) \(extent) \(extent)\" "
            + "preserveAspectRatio=\"none\">"
            + "<radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"0\" cy=\"0\" r=\"0.5\" gradientTransform=\"matrix(\(matrix))\">"
            + stopElements.joined()
            + "</radialGradient>"
            + "<rect x=\"\(origin)\" y=\"\(origin)\" width=\"\(extent)\" height=\"\(extent)\" fill=\"url(#g)\"/></svg>"
        return CSSGradient(
            image: "url('data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())')",
            size: tileSize(width: growth, height: growth, outsets: outsets),
            position: tilePosition(outsets: outsets),
            hasIntrinsicSize: true
        )
    }
}
