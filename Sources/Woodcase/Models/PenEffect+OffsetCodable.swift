//
//  PenEffect+OffsetCodable.swift
//  Woodcase
//

import Foundation

/// A shadow offset's wire form: `x` and `y`, plus — from a file — any other key, kept in
/// ``PenEffect/PenOffset/extras``.
public extension PenEffect.PenOffset {
    /// Decodes an offset, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing or malformed `x` or `y`, or — in
    ///   ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x: container.decode(PenValue<Double>.self, forKey: .x),
            y: container.decode(PenValue<Double>.self, forKey: .y),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a shadow offset")
        )
    }

    /// Encodes the offset, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}
