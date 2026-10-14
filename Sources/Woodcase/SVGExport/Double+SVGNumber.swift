//
//  Double+SVGNumber.swift
//  Woodcase
//

import Foundation

extension Double {
    /// The number as SVG writes a coordinate: at most four decimal places, trailing zeros
    /// and a trailing point dropped, and never `-0`.
    ///
    /// Four places is a ten-thousandth of a point — far below a device pixel at any zoom a
    /// design is viewed at — and keeps a path's data a third the length full precision would.
    var svgNumber: String {
        svgNumber(places: 4)
    }

    /// The number as SVG writes an opacity: at most three decimal places, enough to tell
    /// every 8-bit alpha apart.
    var svgOpacity: String {
        svgNumber(places: 3)
    }

    /// The number rounded to `places` decimals, trimmed.
    private func svgNumber(places: Int) -> String {
        guard isFinite else { return "0" }
        let scale = pow(10, Double(places))
        let rounded = (self * scale).rounded() / scale
        if rounded == 0 { return "0" }
        var text = String(format: "%.\(places)f", rounded)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
