//
//  PenFill+NestedCodable.swift
//  Woodcase
//

import Foundation

/// The wire form of the objects nested inside a gradient fill: each keeps the keys it
/// does not claim in its `extras`, as the fill itself does.
public extension PenFill.PenGradientStop {
    /// Decodes a stop, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing or malformed `color` or `position`, or —
    ///   in ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            color: container.decode(PenValue<String>.self, forKey: .color),
            position: container.decode(PenValue<Double>.self, forKey: .position),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a gradient stop")
        )
    }

    /// Encodes the stop, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(position, forKey: .position)
    }
}

public extension PenFill.PenFillPosition {
    /// Decodes a gradient's center, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a malformed coordinate, or — in
    ///   ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x: container.decodeIfPresent(Double.self, forKey: .x),
            y: container.decodeIfPresent(Double.self, forKey: .y),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a gradient center")
        )
    }

    /// Encodes the center, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(x, forKey: .x)
        try container.encodeIfPresent(y, forKey: .y)
    }
}

public extension PenFill.PenFillSize {
    /// Decodes a gradient's size, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a malformed dimension, or — in
    ///   ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: container.decodeIfPresent(PenValue<Double>.self, forKey: .width),
            height: container.decodeIfPresent(PenValue<Double>.self, forKey: .height),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a gradient size")
        )
    }

    /// Encodes the size, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
    }
}
