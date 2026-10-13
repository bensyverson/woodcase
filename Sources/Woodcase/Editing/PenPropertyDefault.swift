//
//  PenPropertyDefault.swift
//  Woodcase
//

import Foundation

/// What a property is when a node leaves it unset: the value the layout engine and the
/// renderer use in its place.
///
/// An inspector shows it rather than an empty control — a frame with no `layout` lays
/// out horizontally — and an "add" that writes it changes nothing on the canvas. Most
/// defaults are a literal the file could hold (``value``); a text's line height and
/// letter spacing are not, because they come from the font (``Derivation``).
///
/// ``PenSchemaTable/Property/default`` carries one per property that has one;
/// `PenSchemaDefaultEngineTests` draws every literal default against the property left
/// unset, so the schema cannot name a value the engine does not use.
///
/// ```swift
/// PenSchema.field("kind.layout", for: .frame)?.default      // .string("horizontal")
/// PenSchema.field("kind.lineHeight", for: .text)?.default   // .derived(.fontLineHeight)
/// ```
public enum PenPropertyDefault: Friendly {
    /// A number, in the property's own unit.
    case number(Double)

    /// A boolean.
    case boolean(Bool)

    /// A string as the file writes it: one of the property's spellings, a family name,
    /// a weight.
    case string(String)

    /// No literal: the engine takes the value from the font the node is set in.
    case derived(Derivation)

    /// Where a value no literal states comes from.
    public enum Derivation: String, Friendly, CaseIterable {
        /// The font's own line height, from its ascent, descent and leading.
        case fontLineHeight

        /// The font's own kerning, with no extra space between characters.
        case fontKerning

        /// How a person reads it: "the font's own line height".
        public var phrase: String {
            switch self {
            case .fontLineHeight: "the font's own line height"
            case .fontKerning: "the font's own kerning"
            }
        }
    }

    /// The default as `woodcase schema` prints it: a spelling quoted as the file writes
    /// it (`"horizontal"`), a number or a boolean bare (`16`, `true`), and a derived one
    /// as where it comes from ("the font's own line height").
    public var summary: String {
        switch self {
        case let .number(number): PenValueConstraint.spell(number)
        case let .boolean(flag): String(flag)
        case let .string(text): "\"\(text)\""
        case let .derived(derivation): derivation.phrase
        }
    }

    /// The default as the file would write it, or `nil` for a derived one.
    public var value: AnyCodable? {
        switch self {
        case let .number(number): number.rounded() == number && abs(number) < 1e15 ? .int(Int(number)) : .double(number)
        case let .boolean(flag): .bool(flag)
        case let .string(text): .string(text)
        case .derived: nil
        }
    }
}
