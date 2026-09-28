//
//  PenMeshPoint+ObjectCodable.swift
//  Woodcase
//

import Foundation

/// An object-form mesh vertex's wire form: a `position` and up to four handles, plus —
/// from a file — any other key, kept in ``PenMeshPoint/Object/extras``.
public extension PenMeshPoint.Object {
    /// Decodes an object-form vertex, keeping any key it does not claim.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing or malformed `position`, a malformed
    ///   handle, or — in ``PenDecodingMode/authoring`` — an unclaimed key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            position: container.decode(PenMeshPoint.Vector.self, forKey: .position),
            leftHandle: container.decodeIfPresent(PenMeshPoint.Vector.self, forKey: .leftHandle),
            rightHandle: container.decodeIfPresent(PenMeshPoint.Vector.self, forKey: .rightHandle),
            topHandle: container.decodeIfPresent(PenMeshPoint.Vector.self, forKey: .topHandle),
            bottomHandle: container.decodeIfPresent(PenMeshPoint.Vector.self, forKey: .bottomHandle),
            extras: PenExtras.capture(from: decoder, claiming: CodingKeys.self, describing: "a mesh point")
        )
    }

    /// Encodes the vertex, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(leftHandle, forKey: .leftHandle)
        try container.encodeIfPresent(rightHandle, forKey: .rightHandle)
        try container.encodeIfPresent(topHandle, forKey: .topHandle)
        try container.encodeIfPresent(bottomHandle, forKey: .bottomHandle)
    }
}
