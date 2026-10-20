//
//  FigmaClipboardPayload+HTML.swift
//  Woodcase
//

import Foundation

extension FigmaClipboardPayload {
    /// The markers around each section's base64, inside its attribute's decoded value.
    static func markers(for section: FigmaDecodeError.Section) -> (open: [UInt8], close: [UInt8]) {
        switch section {
        case .metadata: (Array("(figmeta)".utf8), Array("(/figmeta)".utf8))
        case .buffer: (Array("(figma)".utf8), Array("(/figma)".utf8))
        }
    }

    /// The attribute each section lives in.
    static func attribute(for section: FigmaDecodeError.Section) -> [UInt8] {
        switch section {
        case .metadata: Array("data-metadata".utf8)
        case .buffer: Array("data-buffer".utf8)
        }
    }

    /// `section`'s bytes: its attribute's value, character references decoded, the base64
    /// between its markers decoded.
    static func section(_ section: FigmaDecodeError.Section, in html: [UInt8]) throws(FigmaDecodeError) -> Data {
        guard let raw = attributeValue(named: attribute(for: section), in: html) else {
            throw .missingSection(section)
        }
        let value = decodingCharacterReferences(raw)
        let (open, close) = markers(for: section)
        guard let start = value.firstRange(of: open)?.upperBound,
              let end = value[start...].firstRange(of: close)?.lowerBound
        else { throw .missingSection(section) }
        let base64 = value[start ..< end].filter { !isWhitespace($0) }
        guard let decoded = Data(base64Encoded: Data(base64)) else { throw .invalidBase64(section) }
        return decoded
    }

    /// The quoted value of the first attribute called `name`, or `nil` when no such
    /// attribute has a terminated value.
    static func attributeValue(named name: [UInt8], in html: [UInt8]) -> ArraySlice<UInt8>? {
        var searchStart = html.startIndex
        while let range = html[searchStart...].firstRange(of: name) {
            searchStart = range.upperBound
            guard range.lowerBound > html.startIndex, isWhitespace(html[range.lowerBound - 1]) else { continue }
            var index = skippingWhitespace(html, from: range.upperBound)
            guard index < html.endIndex, html[index] == UInt8(ascii: "=") else { continue }
            index = skippingWhitespace(html, from: index + 1)
            guard index < html.endIndex, html[index] == UInt8(ascii: "\"") || html[index] == UInt8(ascii: "'") else {
                continue
            }
            let quote = html[index]
            guard let close = html[(index + 1)...].firstIndex(of: quote) else { return nil }
            return html[(index + 1) ..< close]
        }
        return nil
    }

    /// `bytes` with HTML character references — `&lt;`, `&gt;`, `&amp;`, `&quot;`,
    /// `&apos;`, `&#NN;` and `&#xHH;` — replaced by the UTF-8 of what they name. Any other
    /// `&` stays as it is.
    static func decodingCharacterReferences(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            guard bytes[index] == UInt8(ascii: "&"),
                  let semicolon = bytes[index ..< min(index + longestReference, bytes.endIndex)]
                  .firstIndex(of: UInt8(ascii: ";")),
                  let scalar = referencedScalar(String(decoding: bytes[(index + 1) ..< semicolon], as: UTF8.self))
            else {
                result.append(bytes[index])
                index += 1
                continue
            }
            result.append(contentsOf: Array(String(Character(scalar)).utf8))
            index = semicolon + 1
        }
        return result
    }

    /// The longest reference read, `&` through `;`: `&#x10FFFF;`, with room for zeros.
    private static let longestReference = 12

    /// The scalar a reference's name (between `&` and `;`) stands for, if it is one of
    /// the forms ``decodingCharacterReferences(_:)`` reads.
    private static func referencedScalar(_ name: String) -> Unicode.Scalar? {
        switch name {
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        default: break
        }
        guard name.first == "#" else { return nil }
        let digits = name.dropFirst()
        let number: UInt32? = if digits.first == "x" || digits.first == "X" {
            UInt32(digits.dropFirst(), radix: 16)
        } else {
            UInt32(digits, radix: 10)
        }
        return number.flatMap(Unicode.Scalar.init)
    }

    /// The first index at or after `index` that is not ASCII whitespace.
    private static func skippingWhitespace(_ bytes: [UInt8], from index: Int) -> Int {
        var index = index
        while index < bytes.endIndex, isWhitespace(bytes[index]) {
            index += 1
        }
        return index
    }

    /// Whether `byte` is HTML's ASCII whitespace: space, tab, line feed, form feed or
    /// carriage return.
    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }
}
