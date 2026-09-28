//
//  PenThemedValue+Codable.swift
//  Woodcase
//

import Foundation

/// A themed value's wire form: `value` and an optional `theme`, plus — from a file — any
/// other key, kept in ``PenThemedValue/extras``.
public extension PenThemedValue {
    /// Decodes a themed value, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing `value`, a `theme` that is not a map of
    ///   strings, or — in ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(AnyCodable.self, forKey: .value),
            theme: container.decodeIfPresent([String: String].self, forKey: .theme),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a themed value")
        )
    }

    /// Encodes the themed value, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(theme, forKey: .theme)
    }
}
