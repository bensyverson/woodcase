//
//  PenVariable+Codable.swift
//  Woodcase
//

import Foundation

/// A variable definition's wire form: `type` and `value`, plus — from a file — any other
/// key, kept in ``PenVariable/extras``.
public extension PenVariable {
    /// Decodes a definition, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing or unknown `type`, a missing `value`, or —
    ///   in ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            type: container.decode(PenVariableType.self, forKey: .type),
            value: container.decode(PenVariableValue.self, forKey: .value),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a variable definition")
        )
    }

    /// Encodes the definition, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
    }
}
