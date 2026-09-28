//
//  ReactEmitter+CSSNumber.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// A number as CSS or SVG writes it: an integer bare, otherwise at most five decimals
    /// with trailing zeros dropped, and never `-0`.
    static func cssNumber(_ value: Double, decimals: Int = 5) -> String {
        let scale = pow(10, Double(decimals))
        let rounded = (value * scale).rounded() / scale
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
        var text = String(format: "%.\(decimals)f", rounded)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
