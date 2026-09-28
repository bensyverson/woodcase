//
//  PenExtras+Capture.swift
//  Woodcase
//

import Foundation

/// How extras are read out of, and written back into, the .pen object that carries them.
///
/// A .pen object is flat: the keys the model claims and the keys it does not sit side by
/// side. So an owner decodes its typed properties from the decoder as usual, then hands
/// the *same* decoder here with the set of keys it claims; whatever else the object holds
/// is an extra. On the way out the owner encodes its typed properties and then
/// ``encode(into:)`` adds the extras to the same object.
extension PenExtras {
    /// Reads every key of the object at `decoder` that `claimed` does not name.
    ///
    /// In ``PenDecodingMode/file`` the keys are kept. In ``PenDecodingMode/authoring``
    /// the first one is refused with a `DecodingError` that names it and where it was.
    ///
    /// - Parameters:
    ///   - decoder: The decoder positioned at the owning object.
    ///   - claimed: Every key the owner decodes itself.
    ///   - owner: What the object is, for the refusal — `"a frame node"`, `"a color fill"`.
    /// - Returns: The unclaimed keys, empty when there are none.
    /// - Throws: `DecodingError.dataCorrupted` for an unclaimed key in authoring mode, or
    ///   whatever the decoder throws reading one in file mode.
    static func capture(
        from decoder: Decoder,
        claiming claimed: Set<String>,
        describing owner: String
    ) throws -> PenExtras {
        try capture(from: decoder, describing: owner) { claimed.contains($0) }
    }

    /// Reads every key of the object at `decoder` that `Keys` has no case for.
    ///
    /// The form a nested struct uses: its own `CodingKeys` is exactly the set it claims,
    /// and asking the enum costs no set per object decoded.
    ///
    /// - Parameters:
    ///   - decoder: The decoder positioned at the owning object.
    ///   - _: The owner's coding keys; a key with a case is claimed.
    ///   - owner: What the object is, for the refusal — `"a gradient stop"`.
    /// - Returns: The unclaimed keys, empty when there are none.
    /// - Throws: As ``capture(from:claiming:describing:)``.
    static func capture<Keys: CodingKey>(
        from decoder: Decoder,
        claiming _: Keys.Type,
        describing owner: String
    ) throws -> PenExtras {
        try capture(from: decoder, describing: owner) { Keys(stringValue: $0) != nil }
    }

    /// The one capture both forms share; `isClaimed` says whether a key is the owner's.
    private static func capture(
        from decoder: Decoder,
        describing owner: String,
        isClaimed: (String) -> Bool
    ) throws -> PenExtras {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        // The common case — every key claimed — returns before anything is allocated
        // beyond the key list itself.
        guard container.allKeys.contains(where: { !isClaimed($0.stringValue) }) else { return PenExtras() }
        let unclaimed = container.allKeys
            .filter { !isClaimed($0.stringValue) }
            .sorted { $0.stringValue < $1.stringValue }

        if PenDecodingMode.of(decoder) == .authoring, let first = unclaimed.first {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath + [first],
                debugDescription: "\"\(first.stringValue)\" is not a key of \(owner)"
            ))
        }

        var values: [String: AnyCodable] = [:]
        for key in unclaimed {
            values[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
        }
        return PenExtras(values)
    }

    /// Adds the extras to the object the owner is encoding at `encoder`.
    ///
    /// Call it **before** the owner encodes its typed properties: a key written twice
    /// keeps its last value, so a typed property always wins over a stale extra of the
    /// same name.
    ///
    /// - Parameter encoder: The encoder positioned at the owning object.
    /// - Throws: Whatever the encoder throws.
    func encode(into encoder: Encoder) throws {
        guard !isEmpty else { return }
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }
}
