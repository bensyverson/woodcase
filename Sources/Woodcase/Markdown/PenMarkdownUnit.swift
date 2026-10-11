//
//  PenMarkdownUnit.swift
//  Woodcase
//

import Foundation

/// The UTF-16 code units markdown syntax is spelled in: all ASCII, so syntax never
/// splits a surrogate pair.
enum PenMarkdownUnit {
    static let newline = UInt16(UInt8(ascii: "\n"))
    static let carriageReturn = UInt16(UInt8(ascii: "\r"))
    static let space = UInt16(UInt8(ascii: " "))
    static let tab = UInt16(UInt8(ascii: "\t"))
    static let hash = UInt16(UInt8(ascii: "#"))
    static let dash = UInt16(UInt8(ascii: "-"))
    static let asterisk = UInt16(UInt8(ascii: "*"))
    static let plus = UInt16(UInt8(ascii: "+"))
    static let underscore = UInt16(UInt8(ascii: "_"))
    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let backtick = UInt16(UInt8(ascii: "`"))
    static let at = UInt16(UInt8(ascii: "@"))
    static let period = UInt16(UInt8(ascii: "."))
    static let closeParen = UInt16(UInt8(ascii: ")"))
    static let openBracket = UInt16(UInt8(ascii: "["))
    static let closeBracket = UInt16(UInt8(ascii: "]"))
    static let lowerX = UInt16(UInt8(ascii: "x"))
    static let upperX = UInt16(UInt8(ascii: "X"))
    static let zero = UInt16(UInt8(ascii: "0"))
    static let nine = UInt16(UInt8(ascii: "9"))
}
