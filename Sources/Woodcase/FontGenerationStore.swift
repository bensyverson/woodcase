//
//  FontGenerationStore.swift
//  Woodcase
//

import Foundation

/// The bounded, font-set-bound memory behind ``TextSizeCache`` and ``TextInkCache``: what
/// was measured for a key, kept only while the font set it was measured in stands.
///
/// Not thread-safe on its own — a value type its owner keeps behind a lock — and blind to
/// how a value is measured: its owner reads the font set's generation before a lookup
/// and again after measuring, outside the lock, and hands both here.
///
/// ## The font set
///
/// Every value belongs to one ``PenFontRegistry/generation``. The first lookup after the
/// generation moves discards them all, and a value whose measurement straddled a
/// registration is never kept.
///
/// ## The bound
///
/// Two generations of keys rather than an exact least-recently-used list: new values go
/// into a young generation, a value read from the old one is moved into the young one,
/// and when the young generation holds ``generationSize`` values the old one is dropped and
/// the young one takes its place. Every operation is a dictionary lookup, a value used
/// since the last turn always survives the next, and the store never holds more than
/// twice ``generationSize``.
struct FontGenerationStore<Key: Hashable, Value> {
    /// The ``PenFontRegistry/generation`` every value was measured at.
    private(set) var fontGeneration: Int
    /// The most values one generation of keys holds: half the owner's capacity.
    let generationSize: Int
    /// The values stored or read since the last turn.
    private var young: [Key: Value] = [:]
    /// The values of the turn before, dropped at the next turn.
    private var old: [Key: Value] = [:]
    /// How many values were measured — kept or not — for the tests that prove one was reused.
    private(set) var measured = 0

    /// Creates an empty store.
    ///
    /// - Parameters:
    ///   - capacity: The most values it holds; at least 2.
    ///   - fontGeneration: The font set's generation now.
    init(capacity: Int, fontGeneration: Int) {
        precondition(capacity >= 2, "a font generation store holds at least two values")
        generationSize = capacity / 2
        self.fontGeneration = fontGeneration
    }

    /// How many values the store holds.
    var count: Int {
        young.count + old.count
    }

    /// The value kept for a key in the font set `generation` names, moved into the young
    /// generation when it was old; every value is discarded first when the font set moved.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - generation: The font set's generation, read before the lookup.
    /// - Returns: The value, or `nil` when there is none to trust.
    mutating func value(for key: Key, at generation: Int) -> Value? {
        if fontGeneration != generation {
            young.removeAll(keepingCapacity: true)
            old.removeAll()
            fontGeneration = generation
        }
        if let value = young[key] { return value }
        guard let value = old.removeValue(forKey: key) else { return nil }
        insert(value, for: key)
        return value
    }

    /// Records a measurement, and keeps its value when the font set stood still while it
    /// was measured.
    ///
    /// - Parameters:
    ///   - value: The measured value.
    ///   - key: Its key.
    ///   - before: The font set's generation read before measuring.
    ///   - after: The font set's generation read after measuring.
    mutating func keep(_ value: Value, for key: Key, measuredFrom before: Int, to after: Int) {
        measured += 1
        guard after == before, fontGeneration == before else { return }
        insert(value, for: key)
    }

    /// Puts a value in the young generation, turning the generations first when it is full.
    private mutating func insert(_ value: Value, for key: Key) {
        if young[key] == nil, young.count >= generationSize {
            old = young
            young = [:]
            young.reserveCapacity(generationSize)
        }
        young[key] = value
    }
}
