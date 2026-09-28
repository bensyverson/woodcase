//
//  FNV1a.swift
//  Woodcase
//

import Foundation

/// An incremental 64-bit FNV-1a hasher.
///
/// Used to compute revision tokens (see `EditableDocument+Revision.swift`), which
/// must be deterministic across processes and platforms — unlike Swift's
/// per-process-seeded `Hasher`, two peers computing a revision for identical
/// content must get the same answer. Fold bytes in with ``combine(_:)-(some Sequence<UInt8>)``
/// or ``combine(_:)-(String)`` in the order they should be hashed, then read
/// ``finalize()`` for the raw 64-bit value or ``hexString`` for its 16-character
/// lowercase hex rendering.
struct FNV1aHasher {
    /// The FNV-1a 64-bit offset basis — also the hash of an empty input.
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    /// The FNV-1a 64-bit prime.
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    private var value: UInt64 = FNV1aHasher.offsetBasis

    /// Creates a hasher in its initial state, equivalent to hashing an empty input.
    init() {}

    /// Folds a sequence of bytes into the running hash, in order.
    mutating func combine(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            value ^= UInt64(byte)
            value = value &* Self.prime
        }
    }

    /// Folds a string's UTF-8 bytes into the running hash.
    mutating func combine(_ string: String) {
        combine(string.utf8)
    }

    /// The current 64-bit hash value.
    func finalize() -> UInt64 {
        value
    }

    /// The current hash, rendered as 16 lowercase hex characters.
    var hexString: String {
        var hex = String(value, radix: 16, uppercase: false)
        if hex.count < 16 {
            hex = String(repeating: "0", count: 16 - hex.count) + hex
        }
        return hex
    }
}
