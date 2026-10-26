//
//  SeedFingerprint.swift
//  Woodcase
//

import CryptoKit
import Foundation

/// A digest of the document a CRDT replica was seeded from.
///
/// Replicas converge only if they started from the same document: a ``CRDTDocument``
/// built from a ``PenDocument`` gives the document's own nodes the genesis positions
/// (``PeerID/genesis``) and the zero timestamp, so two replicas seeded from different
/// documents share ids that mean different things, and their operations cannot be mixed.
/// The fingerprint lets peers check that before exchanging any: every replica seeded from
/// an equal document reports the same one, whatever its ``PeerID``, and a replica that
/// joined from a ``CRDTSnapshot`` or ``CRDTStateTransfer`` reports its donor's.
///
/// It is SHA-256 over the bytes `woodcase.crdt-seed.v1` and a newline, followed by the
/// seed's canonical encoding (``canonicalEncoding(of:)``). The prefix names the scheme, so
/// a change to the encoding changes every fingerprint rather than colliding with the old
/// ones. See <doc:CRDTArchitecture#Seed-Fingerprint>.
public struct SeedFingerprint: Friendly {
    /// The length of a fingerprint in bytes: a SHA-256 digest's.
    public static let byteCount = SHA256.byteCount

    /// The prefix hashed before the canonical encoding, naming the scheme's version.
    static let schemePrefix = Data("woodcase.crdt-seed.v1\n".utf8)

    /// The digest: ``byteCount`` bytes.
    public let bytes: Data

    /// Fingerprints a document as a replica's seed.
    ///
    /// - Parameter document: The document a replica is seeded from.
    public init(of document: PenDocument) {
        bytes = Data(SHA256.hash(data: Self.schemePrefix + Self.canonicalEncoding(of: document)))
    }

    /// Wraps a digest computed earlier, such as one read back from storage.
    ///
    /// - Parameter bytes: The digest.
    /// - Returns: `nil` unless `bytes` holds exactly ``byteCount`` bytes.
    public init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    /// The bytes a document's fingerprint is taken over: compact JSON with every
    /// object's keys sorted and slashes unescaped.
    ///
    /// Equal documents encode to equal bytes. Sorting the keys at output removes every
    /// dictionary's iteration order, which Swift seeds afresh in each process; the model
    /// holds no set, so no array comes from one; and `JSONEncoder` writes a number in the
    /// shortest form that reads back as the same value (`0.1`, not `0.10000000000000001`).
    /// A non-finite number, which JSON cannot hold, is written as a string, so encoding
    /// cannot fail on one.
    ///
    /// - Parameter document: The document to encode.
    /// - Returns: The canonical encoding.
    static func canonicalEncoding(of document: PenDocument) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        do {
            return try encoder.encode(document)
        } catch {
            // Unreachable: with non-finite numbers written as strings, nothing in the
            // model throws while encoding. Should that change, the document's reflection
            // still separates documents, where an empty encoding would make every such
            // seed collide.
            return Data("unencodable:\(String(reflecting: document))".utf8)
        }
    }

    /// Decodes a fingerprint, refusing one that is not ``byteCount`` bytes.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` for a digest of the wrong length.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let bytes = try container.decode(Data.self)
        guard let fingerprint = SeedFingerprint(bytes: bytes) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A seed fingerprint is \(Self.byteCount) bytes; this one is \(bytes.count)."
            )
        }
        self = fingerprint
    }

    /// Encodes the fingerprint as its bytes alone.
    ///
    /// - Parameter encoder: The encoder to write to.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }
}
