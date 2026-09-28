//
//  PenNode+ConnectionEndpointCodable.swift
//  Woodcase
//

import Foundation

/// A connection endpoint's wire form: `path` and `anchor`, plus — from a file — any other
/// key, kept in ``PenNode/ConnectionData/Endpoint/extras``.
public extension PenNode.ConnectionData.Endpoint {
    /// Decodes an endpoint, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing `path`, a missing or unknown `anchor`, or
    ///   — in ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            path: container.decode(String.self, forKey: .path),
            anchor: container.decode(PenNode.ConnectionData.Anchor.self, forKey: .anchor),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a connection endpoint")
        )
    }

    /// Encodes the endpoint, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(anchor, forKey: .anchor)
    }
}
