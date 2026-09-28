//
//  PenStrokeWidth+NestedCodable.swift
//  Woodcase
//

import Foundation

/// The wire form of the per-side object nested inside `strokeWidth`: it keeps the keys it
/// does not claim in its `extras`, as the other nested payloads do.
public extension PenStrokeWidth.Sides {
    /// Decodes the per-side object, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a malformed side, or — in ``PenDecodingMode/authoring``
    ///   — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            top: container.decodeIfPresent(PenValue<Double>.self, forKey: .top),
            right: container.decodeIfPresent(PenValue<Double>.self, forKey: .right),
            bottom: container.decodeIfPresent(PenValue<Double>.self, forKey: .bottom),
            left: container.decodeIfPresent(PenValue<Double>.self, forKey: .left),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a per-side width")
        )
    }

    /// Encodes the per-side object, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(top, forKey: .top)
        try container.encodeIfPresent(right, forKey: .right)
        try container.encodeIfPresent(bottom, forKey: .bottom)
        try container.encodeIfPresent(left, forKey: .left)
    }
}
