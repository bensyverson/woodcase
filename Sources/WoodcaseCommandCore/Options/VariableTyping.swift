//
//  VariableTyping.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Turns a command line's `name=value` literal into a typed .pen variable value.
///
/// A `.pen` variable declares a type, and the same characters mean different things
/// under different ones — `16` is a number or the string `"16"`, `#FF6600` is a color
/// or a string. ``VarsSet`` settles the type first (`--type`, else the variable's
/// existing declaration, else ``inferredType(of:)``) and then asks ``value(of:as:)``
/// for the literal *as that type*, so the type a variable's references depend on never
/// changes by accident.
///
/// ```swift
/// VariableTyping.inferredType(of: "#FF6600")     // .color
/// VariableTyping.value(of: "16", as: .string)    // .string("16")
/// VariableTyping.value(of: "wide", as: .number)  // nil — refused
/// ```
enum VariableTyping {
    /// The type a literal reads as with nothing else to go on.
    ///
    /// In order: a hex color, `true`/`false`, a finite number, else a string. `rgba()`
    /// and other CSS color functions are *not* colors — the 2.17 schema's `Color` is
    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA` and nothing else reads back, so they fall
    /// through to string rather than being written as a color Pen cannot render.
    ///
    /// - Parameter literal: The text on the right of the equals sign.
    /// - Returns: The inferred type, or `nil` for a `$reference`, which takes its type
    ///   from the variable it names.
    static func inferredType(of literal: String) -> PenVariableType? {
        if literal.hasPrefix(referencePrefix) { return nil }
        if isHexColor(literal) { return .color }
        if literal == "true" || literal == "false" { return .boolean }
        if let number = Double(literal), number.isFinite { return .number }
        return .string
    }

    /// The literal as a value of a declared type.
    ///
    /// A `$reference` is legal under every type: the schema's value slot is
    /// `ColorOrVariable`, `NumberOrVariable` and so on, and what it resolves to is the
    /// resolver's business, not this one's.
    ///
    /// - Parameters:
    ///   - literal: The text on the right of the equals sign.
    ///   - type: The type the variable declares.
    /// - Returns: The value to store, or `nil` when the literal is not one of that type.
    static func value(of literal: String, as type: PenVariableType) -> AnyCodable? {
        if literal.hasPrefix(referencePrefix) { return .string(literal) }
        switch type {
        case .color:
            return isHexColor(literal) ? .string(literal) : nil
        case .boolean:
            if literal == "true" { return .bool(true) }
            if literal == "false" { return .bool(false) }
            return nil
        case .number:
            guard let number = Double(literal), number.isFinite else { return nil }
            // An integral number is stored as an integer so an untouched file's numbers
            // round-trip to the same bytes they were read from.
            if let integer = Int(exactly: number) { return .int(integer) }
            return .double(number)
        case .string:
            return .string(literal)
        }
    }

    /// Whether a literal is a hex color the .pen format can hold.
    ///
    /// - Parameter literal: The text to test.
    /// - Returns: `true` for `#RGB`, `#RRGGBB` and `#RRGGBBAA`, in either case. The
    ///   `#` is required: without it `abc` would be a color rather than a string.
    static func isHexColor(_ literal: String) -> Bool {
        guard literal.hasPrefix("#") else { return false }
        let digits = literal.dropFirst()
        guard hexColorWidths.contains(digits.count) else { return false }
        return digits.allSatisfy(\.isHexDigit)
    }

    /// What every value that names another variable begins with.
    static let referencePrefix = "$"

    /// An example of each type, for the message a refused value gets.
    ///
    /// - Parameter type: The type to describe.
    /// - Returns: A literal of that type the reader can copy.
    static func example(of type: PenVariableType) -> String {
        switch type {
        case .color: "#FF6600"
        case .number: "16"
        case .boolean: "true"
        case .string: "any text"
        }
    }

    /// The digit counts of the schema's three color widths.
    private static let hexColorWidths: Set<Int> = [3, 6, 8]
}
