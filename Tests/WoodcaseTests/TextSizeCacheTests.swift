//
//  TextSizeCacheTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

/// A text's size is measured once per font set, and never answered across a change to it.
///
/// ``TextSizeCache`` sits in front of a ``TextMeasurer`` and is shared by the settles of
/// one run, so the second of two layouts over mostly the same texts typesets only the
/// ones that changed. Every argument the measurer takes is part of the key; the font set
/// is not an argument, so the cache belongs to one ``PenFontRegistry/generation`` and
/// starts again when it moves.
///
/// The generation is injected here, so a font registered by another suite running in
/// parallel cannot turn an exact count into a flake; one test reads the real registry.
struct TextSizeCacheTests {
    /// A measurer that records every call and answers a size derived from its arguments,
    /// so a cached answer for the wrong key would show.
    final class RecordingMeasurer: Sendable {
        private let calls = Mutex(0)

        /// What happens during each call, before it answers: a test registers fonts here.
        private let during: @Sendable () -> Void

        init(during: @escaping @Sendable () -> Void = {}) {
            self.during = during
        }

        /// How many texts reached the measurer.
        var count: Int {
            calls.withLock { $0 }
        }

        /// The measurer to wrap.
        var measurer: TextMeasurer {
            { [self] text, _, fontSize, _, _, letterSpacing, _, maxWidth in
                calls.withLock { $0 += 1 }
                during()
                let width = Double(text.count) * (fontSize ?? 16) + (letterSpacing ?? 0)
                return (width: min(width, maxWidth ?? .infinity), height: fontSize ?? 16)
            }
        }
    }

    /// A font generation a test moves by hand.
    final class Generation: Sendable {
        private let value = Mutex(0)

        /// The current generation.
        var current: Int {
            value.withLock { $0 }
        }

        /// Records that fonts were registered.
        func advance() {
            value.withLock { $0 += 1 }
        }
    }

    /// Measures with every argument named, so a test varies one at a time.
    private static func measure(
        _ measurer: TextMeasurer,
        _ text: String = "Hello",
        family: String? = "Inter",
        size: Double? = 14,
        weight: String? = "400",
        style: String? = "normal",
        letterSpacing: Double? = 0,
        lineHeight: Double? = 1.2,
        maxWidth: Double? = 200
    ) -> (width: Double, height: Double) {
        measurer(text, family, size, weight, style, letterSpacing, lineHeight, maxWidth)
    }

    @Test("the same text with the same attributes is measured once")
    func aRepeatIsAnswered() {
        let base = RecordingMeasurer()
        let generation = Generation()
        let cache = TextSizeCache(measuring: base.measurer, fontGeneration: { generation.current })

        let first = Self.measure(cache.measurer)
        let second = Self.measure(cache.measurer)

        #expect(base.count == 1)
        #expect(first == second)
    }

    @Test("every argument the measurer takes is part of the key")
    func everyArgumentIsKeyed() {
        let base = RecordingMeasurer()
        let generation = Generation()
        let cache = TextSizeCache(measuring: base.measurer, fontGeneration: { generation.current })
        let measurer = cache.measurer

        _ = Self.measure(measurer)
        _ = Self.measure(measurer, "Hello!")
        _ = Self.measure(measurer, family: "IBM Plex Sans")
        _ = Self.measure(measurer, size: 15)
        _ = Self.measure(measurer, weight: "700")
        _ = Self.measure(measurer, style: "italic")
        _ = Self.measure(measurer, letterSpacing: 1)
        _ = Self.measure(measurer, lineHeight: 1.5)
        _ = Self.measure(measurer, maxWidth: 100)
        _ = Self.measure(measurer, family: nil, size: nil, weight: nil, style: nil,
                         letterSpacing: nil, lineHeight: nil, maxWidth: nil)
        _ = Self.measure(measurer)

        #expect(base.count == 10, "a variant was answered from another's entry, or a repeat was not")
    }

    @Test("a font registration between two measurements measures again")
    func aRegistrationDiscardsTheSizes() {
        let base = RecordingMeasurer()
        let generation = Generation()
        let cache = TextSizeCache(measuring: base.measurer, fontGeneration: { generation.current })

        _ = Self.measure(cache.measurer)
        generation.advance()
        _ = Self.measure(cache.measurer)
        _ = Self.measure(cache.measurer)

        #expect(base.count == 2)
    }

    @Test("a size measured while fonts were being registered is not kept")
    func aStraddlingMeasurementIsDropped() {
        let generation = Generation()
        let registeredOnce = Mutex(false)
        let base = RecordingMeasurer(during: {
            let first = registeredOnce.withLock { done in
                defer { done = true }
                return !done
            }
            if first { generation.advance() }
        })
        let cache = TextSizeCache(measuring: base.measurer, fontGeneration: { generation.current })

        _ = Self.measure(cache.measurer)
        _ = Self.measure(cache.measurer)
        _ = Self.measure(cache.measurer)

        #expect(base.count == 2, "the first size described the font set before the registration")
    }

    @Test("by default the font set is the process's registry")
    func theDefaultGenerationIsTheRegistry() {
        let base = RecordingMeasurer()
        let cache = TextSizeCache(measuring: base.measurer)

        _ = Self.measure(cache.measurer)
        PenFontRegistry.didRegisterFonts()
        _ = Self.measure(cache.measurer)
        _ = Self.measure(cache.measurer)

        #expect(base.count == 2)
    }
}
