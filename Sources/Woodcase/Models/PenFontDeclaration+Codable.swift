//
//  PenFontDeclaration+Codable.swift
//  Woodcase
//

import Foundation

/// A font declaration's wire form: the four keys Pen's validator accepts, plus — from a
/// file — any other key, kept in ``PenFontDeclaration/extras``.
public extension PenFontDeclaration {
    /// The keys a declaration claims.
    internal enum CodingKeys: String, CodingKey, CaseIterable {
        case name, url, style, weight
    }

    /// Decodes a declaration.
    ///
    /// - Parameter decoder: The decoder to read from. In ``PenDecodingMode/authoring`` a
    ///   key the declaration does not claim is refused rather than kept.
    /// - Throws: `DecodingError` for a missing `name` or `url`, a `style` other than
    ///   `normal` or `italic`, a malformed `weight`, or an unclaimed key in authoring mode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            url: container.decode(String.self, forKey: .url),
            style: container.decodeIfPresent(Style.self, forKey: .style),
            weight: container.decodeIfPresent(Weight.self, forKey: .weight),
            extras: PenExtras.capture(
                from: decoder,
                claiming: Set(CodingKeys.allCases.map(\.stringValue)),
                describing: "a font declaration"
            )
        )
    }

    /// Encodes the declaration, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(weight, forKey: .weight)
    }
}

public extension PenFontDeclaration.Weight {
    /// Decodes a weight from a number or a two-number array.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` for anything else — a string such as
    ///   `"100 900"`, an array of any other length, an object.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(Double.self) {
            self = .single(single)
            return
        }
        if let pair = try? container.decode([Double].self), pair.count == 2 {
            self = .range(from: pair[0], to: pair[1])
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "A font weight is a number, or [min, max] for a variable font"
        )
    }

    /// Encodes the weight as a number or a two-number array.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(value):
            try container.encode(value)
        case let .range(from, to):
            try container.encode([from, to])
        }
    }
}
