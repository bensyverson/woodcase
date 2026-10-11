//
//  PenMarkdownInline+Characters.swift
//  Woodcase
//

import Foundation

extension PenMarkdownInline {
    /// The scalar starting at a UTF-16 offset within the line, and how many code units
    /// it takes; `nil` at the line's end.
    func scalar(at offset: Int, in units: [UInt16]) -> (scalar: Unicode.Scalar, width: Int)? {
        guard offset >= range.lowerBound, offset < range.upperBound else { return nil }
        let unit = units[offset]
        if UTF16.isLeadSurrogate(unit), offset + 1 < range.upperBound, UTF16.isTrailSurrogate(units[offset + 1]) {
            return (UTF16.decode(UTF16.EncodedScalar([unit, units[offset + 1]])), 2)
        }
        return (Unicode.Scalar(unit) ?? Self.replacement, 1)
    }

    /// The scalar ending just before a UTF-16 offset within the line; `nil` at its start.
    func scalar(before offset: Int, in units: [UInt16]) -> Unicode.Scalar? {
        guard offset > range.lowerBound, offset <= range.upperBound else { return nil }
        let unit = units[offset - 1]
        if UTF16.isTrailSurrogate(unit), offset - 2 >= range.lowerBound, UTF16.isLeadSurrogate(units[offset - 2]) {
            return UTF16.decode(UTF16.EncodedScalar([units[offset - 2], unit]))
        }
        return Unicode.Scalar(unit) ?? Self.replacement
    }

    /// What a lone surrogate reads as.
    private static let replacement: Unicode.Scalar = "\u{FFFD}"

    /// Whether a scalar is whitespace for flanking; a line's edge (`nil`) counts as one.
    static func isWhitespace(_ scalar: Unicode.Scalar?) -> Bool {
        scalar.map(\.properties.isWhitespace) ?? true
    }

    /// Whether a scalar is punctuation or a symbol for flanking, as CommonMark counts it.
    static func isPunctuation(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        if scalar.isASCII { return isASCIIPunctuation(UInt16(scalar.value)) }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    /// Whether a code unit is ASCII punctuation, which a backslash may escape.
    static func isASCIIPunctuation(_ unit: UInt16) -> Bool {
        (0x21 ... 0x2F).contains(unit) || (0x3A ... 0x40).contains(unit)
            || (0x5B ... 0x60).contains(unit) || (0x7B ... 0x7E).contains(unit)
    }

    /// Whether a scalar may be part of a mentioned name: a letter, a digit, `-`, `_`
    /// or `.`.
    static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil || "-_.".unicodeScalars.contains(scalar)
    }
}
