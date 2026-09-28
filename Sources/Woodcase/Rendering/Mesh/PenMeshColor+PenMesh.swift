//
//  PenMeshColor+PenMesh.swift
//  Woodcase
//

import Foundation

/// Pen's own reading of a mesh vertex colour, which is not ``PenHexColor``'s grammar.
///
/// Measured against Pen's exports of `render-mesh-colors.pen` (`scripts/pen-oracle`,
/// `pen` CLI 0.3.9, 2026-09-27): Pen drops one leading `#`, then reads the rest by its
/// length in UTF-16 code units. Three digits are read one by one, each doubled, a digit
/// that is not hex reading 0 (`red` is `#00EEDD`). Six or eight are read as one number
/// by JavaScript's `parseInt(digits, 16)` — leading whitespace, a sign and `0x` skipped,
/// then the longest run of hex digits, no digits reading 0 — and that number's low 32 bits
/// split into bytes: `RRGGBB` opaque, or `RRGGBBAA` (`#eGeGeG` is `#00000E`, `#-f-f-f` is
/// `#FFFFF1`). Any other length, `#RGBA` included, is transparent.
public extension PenMeshColor {
    /// Transparent black: what Pen paints for a vertex colour whose length it cannot read.
    static let transparent = PenMeshColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// Reads a vertex colour string as Pen's mesh reads it (``hexColor(penMesh:)``).
    ///
    /// - Parameter penMesh: The colour string, as the file writes it.
    init(penMesh: String) {
        let unit = Self.hexColor(penMesh: penMesh).unitComponents
        self.init(red: unit[0], green: unit[1], blue: unit[2], alpha: unit[3])
    }

    /// A vertex colour string's channels as Pen's mesh reads them; every string reads as
    /// some colour.
    ///
    /// - Parameter string: The colour string, as the file writes it.
    /// - Returns: The channels, transparent black for a length Pen cannot read.
    static func hexColor(penMesh string: String) -> PenHexColor {
        guard let digits = penMeshDigits(string) else { return PenHexColor(red: 0, green: 0, blue: 0, alpha: 0) }
        if digits.count == 3 {
            let channels = digits.map { UInt8(hexValue($0) ?? 0) * 17 }
            return PenHexColor(red: channels[0], green: channels[1], blue: channels[2])
        }
        let number = UInt32(truncatingIfNeeded: parseInt(digits) ?? 0)
        func byte(_ shift: UInt32) -> UInt8 {
            UInt8(truncatingIfNeeded: number >> shift)
        }
        if digits.count == 6 {
            return PenHexColor(red: byte(16), green: byte(8), blue: byte(0))
        }
        return PenHexColor(red: byte(24), green: byte(16), blue: byte(8), alpha: byte(0))
    }
}

extension PenMeshColor {
    /// A colour string's UTF-16 code units after one leading `#`, when they number 3, 6
    /// or 8 — the lengths Pen's mesh reads; `nil` for any other, which paints nothing.
    static func penMeshDigits(_ string: String) -> [UInt16]? {
        var units = Array(string.utf16)
        if units.first == UInt16(UInt8(ascii: "#")) {
            units.removeFirst()
        }
        return [3, 6, 8].contains(units.count) ? units : nil
    }

    /// A code unit's value as an ASCII hex digit.
    private static func hexValue(_ unit: UInt16) -> Int? {
        guard unit < 128 else { return nil }
        return Character(Unicode.Scalar(UInt8(unit))).hexDigitValue
    }

    /// JavaScript's `parseInt(units, 16)`, `nil` where it gives `NaN`.
    private static func parseInt(_ units: [UInt16]) -> Int64? {
        var rest = units[...].drop(while: isJavaScriptWhitespace)
        var sign: Int64 = 1
        if let first = rest.first, first == UInt16(UInt8(ascii: "+")) || first == UInt16(UInt8(ascii: "-")) {
            sign = first == UInt16(UInt8(ascii: "-")) ? -1 : 1
            rest = rest.dropFirst()
        }
        if rest.count >= 2, rest.first == UInt16(UInt8(ascii: "0")),
           rest.dropFirst().first.map({ $0 | 0x20 == UInt16(UInt8(ascii: "x")) }) == true
        {
            rest = rest.dropFirst(2)
        }
        let digits = rest.prefix { hexValue($0) != nil }.compactMap(hexValue)
        guard !digits.isEmpty else { return nil }
        // Eight digits at most, so the value always fits.
        return sign * digits.reduce(Int64(0)) { $0 * 16 + Int64($1) }
    }

    /// Whether a code unit is JavaScript `WhiteSpace` or `LineTerminator`, which
    /// `parseInt` skips before the number.
    private static func isJavaScriptWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09 ... 0x0D, 0x20, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }
}
