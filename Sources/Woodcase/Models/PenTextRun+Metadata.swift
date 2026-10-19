//
//  PenTextRun+Metadata.swift
//  Woodcase
//

import Foundation

/// One run as `metadata.woodcase.spans` stores it (see ``PenTextSpans/init(metadataValue:)``).
public extension PenTextRun {
    /// The keys a stored run may hold.
    enum WireKey: String, Friendly, CaseIterable {
        /// The first UTF-16 offset covered.
        case start
        /// The UTF-16 offset just past the run.
        case end
        /// The font family.
        case fontFamily
        /// The font size in points.
        case fontSize
        /// The weight, as the format spells it: `"700"`.
        case fontWeight
        /// `"italic"` or `"normal"`.
        case fontStyle
        /// The glyph color, as a hex color.
        case fill
        /// Whether the run is underlined.
        case underline
        /// Whether the run is struck through.
        case strikethrough
        /// The name the run mentions: a non-empty string.
        case mention
        /// The URL the run links to: a non-empty string a URL parses from.
        case link
    }

    /// The format's `fontStyle` for an italic run.
    internal static let italicStyle = "italic"

    /// The format's `fontStyle` for an upright run.
    internal static let normalStyle = "normal"

    /// The run in its stored form: only the keys it sets.
    var metadataValue: AnyCodable {
        var object: [String: AnyCodable] = [WireKey.start.rawValue: .int(start), WireKey.end.rawValue: .int(end)]
        object[WireKey.fontFamily.rawValue] = fontFamily.map(AnyCodable.string)
        object[WireKey.fontSize.rawValue] = fontSize.map(Self.number)
        object[WireKey.fontWeight.rawValue] = fontWeight.map { .string(Self.spelling(ofWeight: $0)) }
        object[WireKey.fontStyle.rawValue] = isItalic.map { .string($0 ? Self.italicStyle : Self.normalStyle) }
        object[WireKey.fill.rawValue] = fill.map { .string($0.hex) }
        object[WireKey.underline.rawValue] = underline.map(AnyCodable.bool)
        object[WireKey.strikethrough.rawValue] = strikethrough.map(AnyCodable.bool)
        object[WireKey.mention.rawValue] = mention.map(AnyCodable.string)
        object[WireKey.link.rawValue] = link.map(AnyCodable.string)
        return .dictionary(object)
    }

    /// Reads one stored run.
    ///
    /// - Parameters:
    ///   - value: The stored run.
    ///   - number: Its place in the list, counting from 1, for a message.
    ///   - textLength: The UTF-16 length of the text the runs were made for.
    /// - Throws: ``PenTextSpans/WireError`` naming the first thing that is wrong.
    internal init(metadataValue value: AnyCodable, number: Int, textLength: Int) throws(PenTextSpans.WireError) {
        func refuse(_ reason: String) -> PenTextSpans.WireError {
            PenTextSpans.WireError(reason: "run \(number) \(reason)")
        }
        guard case let .dictionary(object) = value else { throw refuse("is not an object {start, end, …}") }
        if let extra = object.keys.sorted().first(where: { WireKey(rawValue: $0) == nil }) {
            throw refuse("has an unknown key \"\(extra)\"; a run takes "
                + WireKey.allCases.map(\.rawValue).joined(separator: ", "))
        }
        guard let start = Self.integer(object[WireKey.start.rawValue]),
              let end = Self.integer(object[WireKey.end.rawValue])
        else { throw refuse("needs whole-number start and end") }
        guard start >= 0, start <= end, end <= textLength else {
            throw refuse("covers \(start)..<\(end), outside the text's \(textLength) UTF-16 units")
        }
        self.init(start: start, end: end)

        switch object[WireKey.fontFamily.rawValue] {
        case nil: break
        case let .string(family)? where !family.isEmpty: fontFamily = family
        default: throw refuse("has a fontFamily that is not a family name")
        }
        switch object[WireKey.fontSize.rawValue] {
        case nil: break
        case let value?:
            guard let size = Self.double(value), size > 0 else { throw refuse("has a fontSize that is not a positive number") }
            fontSize = size
        }
        switch object[WireKey.fontWeight.rawValue] {
        case nil: break
        case let value?:
            guard let weight = Self.weight(value) else {
                throw refuse("has a fontWeight that is neither a number from 1 to 1000 nor a keyword such as \"bold\"")
            }
            fontWeight = weight
        }
        switch object[WireKey.fontStyle.rawValue] {
        case nil: break
        case .string(Self.italicStyle)?: isItalic = true
        case .string(Self.normalStyle)?: isItalic = false
        default: throw refuse("has a fontStyle that is neither \"italic\" nor \"normal\"")
        }
        switch object[WireKey.fill.rawValue] {
        case nil: break
        case let .string(text)?:
            guard let color = PenHexColor(text) else { throw refuse("has a fill that is not a hex color: #RRGGBB or #RRGGBBAA") }
            fill = color
        default: throw refuse("has a fill that is not a hex color: #RRGGBB or #RRGGBBAA")
        }
        switch object[WireKey.mention.rawValue] {
        case nil: break
        case let .string(name)? where !name.isEmpty: mention = name
        default: throw refuse("has a mention that is not a name")
        }
        switch object[WireKey.link.rawValue] {
        case nil: break
        case let .string(url)? where !url.isEmpty && URL(string: url) != nil: link = url
        default: throw refuse("has a link that is not a URL")
        }
        for key in [WireKey.underline, .strikethrough] {
            switch object[key.rawValue] {
            case nil: continue
            case let .bool(flag)?: if key == .underline { underline = flag } else { strikethrough = flag }
            default: throw refuse("has a \(key.rawValue) that is not true or false")
            }
        }
    }

    // MARK: - Private

    /// A whole number, written as an integer or an integral double.
    private static func integer(_ value: AnyCodable?) -> Int? {
        switch value {
        case let .int(whole)?: whole
        case let .double(number)? where number.rounded() == number && abs(number) < 1e15: Int(number)
        default: nil
        }
    }

    /// Any number.
    private static func double(_ value: AnyCodable) -> Double? {
        switch value {
        case let .int(whole): Double(whole)
        case let .double(number) where number.isFinite: number
        default: nil
        }
    }

    /// A stored weight: a number, or a string holding a number or a keyword; `nil` for
    /// anything else, or a number outside 1–1000.
    internal static func weight(_ value: AnyCodable) -> Double? {
        let weight: Double? = switch value {
        case let .string(text): Double(text) ?? keywordWeight(text)
        default: double(value)
        }
        guard let weight, weight >= 1, weight <= 1000 else { return nil }
        return weight
    }

    /// The weight a keyword names, or `nil` for a word that names none.
    private static func keywordWeight(_ text: String) -> Double? {
        let weight = PenFontWeight.cssWeight(text)
        let isRegular = ["normal", "regular"].contains(text.lowercased())
        return weight == PenTextStyle.defaultFontWeight && !isRegular ? nil : weight
    }

    /// A weight as the format spells it: `"700"`, or `"450.5"` when not whole.
    private static func spelling(ofWeight weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(weight)
    }

    /// A number in its stored form: an integer when whole.
    private static func number(_ value: Double) -> AnyCodable {
        value.rounded() == value && abs(value) < 1e15 ? .int(Int(value)) : .double(value)
    }
}
