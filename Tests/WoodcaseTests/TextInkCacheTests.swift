//
//  TextInkCacheTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

/// A text's ink is laid out once per font set, and never answered across a change to it.
///
/// ``TextInkCache`` sits behind ``PenLayoutEngine/textInkBounds(of:box:)``, so every
/// painted-extent pass of a process shares the inks of the texts it has seen. Everything
/// the layout reads is part of the key — the text, its style, its runs but their colors,
/// and its box — and the font set is not, so the cache belongs to one
/// ``PenFontRegistry/generation`` and starts again when it moves.
///
/// The generation is injected, as in ``TextSizeCacheTests``, so a font registered by a
/// suite running in parallel cannot turn an exact count into a flake.
struct TextInkCacheTests {
    /// A measurement that counts its calls and answers an ink derived from its key.
    final class RecordingInk: Sendable {
        private let calls = Mutex(0)
        private let during: @Sendable () -> Void

        init(during: @escaping @Sendable () -> Void = {}) {
            self.during = during
        }

        /// How many inks were laid out.
        var count: Int {
            calls.withLock { $0 }
        }

        /// The measurement to hand the cache.
        func measure(_ key: TextInkCache.Key) -> PenRect? {
            calls.withLock { $0 += 1 }
            during()
            guard !key.text.isEmpty else { return nil }
            return PenRect(x: 0, y: 0, width: Double(key.text.count) * key.style.fontSize, height: key.height)
        }
    }

    /// A key with every field named, so a test varies one at a time.
    private static func key(
        _ text: String = "Hello",
        size: Double = 14,
        italic: Bool = false,
        runs: [PenTextRun] = [],
        width: Double = 200,
        height: Double = 20
    ) -> TextInkCache.Key {
        var style = PenTextStyle()
        style.fontSize = size
        style.isItalic = italic
        return TextInkCache.Key(text: text, style: style, runs: runs, width: width, height: height)
    }

    @Test("the same text in the same style and box is laid out once")
    func aRepeatIsAnswered() {
        let ink = RecordingInk()
        let cache = TextInkCache(fontGeneration: { 0 })

        let first = cache.inkBounds(of: Self.key(), measure: ink.measure)
        let second = cache.inkBounds(of: Self.key(), measure: ink.measure)

        #expect(ink.count == 1)
        #expect(first == second)
        #expect(cache.measuredCount == 1)
    }

    @Test("a text with no ink is remembered as having none")
    func noInkIsKept() {
        let ink = RecordingInk()
        let cache = TextInkCache(fontGeneration: { 0 })

        #expect(cache.inkBounds(of: Self.key(""), measure: ink.measure) == nil)
        #expect(cache.inkBounds(of: Self.key(""), measure: ink.measure) == nil)
        #expect(ink.count == 1)
    }

    @Test("the text, its style, its runs and its box are all part of the key")
    func everyInputIsKeyed() {
        let ink = RecordingInk()
        let cache = TextInkCache(fontGeneration: { 0 })

        for key in [
            Self.key(), Self.key("Hello!"), Self.key(size: 15), Self.key(italic: true),
            Self.key(runs: [PenTextRun(start: 0, end: 2, fontWeight: 700)]), Self.key(width: 100),
            Self.key(height: 40), Self.key(),
        ] {
            _ = cache.inkBounds(of: key, measure: ink.measure)
        }

        #expect(ink.count == 7, "a variant was answered from another's entry, or a repeat was not")
    }

    @Test("recoloring a run keeps its ink; restyling it does not")
    func aRunsColorIsNotKeyed() {
        let ink = RecordingInk()
        let cache = TextInkCache(fontGeneration: { 0 })
        let red = PenHexColor(red: 255, green: 0, blue: 0)
        let blue = PenHexColor(red: 0, green: 0, blue: 255)

        _ = cache.inkBounds(of: Self.key(runs: [PenTextRun(start: 0, end: 2, fontWeight: 700, fill: red)]), measure: ink.measure)
        _ = cache.inkBounds(of: Self.key(runs: [PenTextRun(start: 0, end: 2, fontWeight: 700, fill: blue)]), measure: ink.measure)
        _ = cache.inkBounds(of: Self.key(runs: [PenTextRun(start: 0, end: 2, fontWeight: 700)]), measure: ink.measure)
        #expect(ink.count == 1, "a run's fill reached the key")

        _ = cache.inkBounds(of: Self.key(runs: [PenTextRun(start: 0, end: 2, fontWeight: 800, fill: red)]), measure: ink.measure)
        #expect(ink.count == 2)
    }

    @Test("a font registration between two lookups lays the text out again")
    func aRegistrationDiscardsTheInks() {
        let ink = RecordingInk()
        let generation = TextSizeCacheTests.Generation()
        let cache = TextInkCache(fontGeneration: { generation.current })

        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)
        generation.advance()
        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)
        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)

        #expect(ink.count == 2)
    }

    @Test("an ink laid out while fonts were being registered is not kept")
    func aStraddlingLayoutIsDropped() {
        let generation = TextSizeCacheTests.Generation()
        let registeredOnce = Mutex(false)
        let ink = RecordingInk(during: {
            let first = registeredOnce.withLock { done in
                defer { done = true }
                return !done
            }
            if first { generation.advance() }
        })
        let cache = TextInkCache(fontGeneration: { generation.current })

        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)
        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)
        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)

        #expect(ink.count == 2, "the first ink described the font set before the registration")
    }

    @Test("by default the font set is the process's registry")
    func theDefaultGenerationIsTheRegistry() {
        let ink = RecordingInk()
        let cache = TextInkCache()

        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)
        PenFontRegistry.didRegisterFonts()
        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)
        _ = cache.inkBounds(of: Self.key(), measure: ink.measure)

        #expect(ink.count == 2)
    }

    @Test("the cache never holds more inks than its capacity, and forgets the least recently used")
    func theCacheIsBounded() {
        let ink = RecordingInk()
        let cache = TextInkCache(capacity: 4, fontGeneration: { 0 })

        for number in 0 ..< 50 {
            _ = cache.inkBounds(of: Self.key("Text \(number)"), measure: ink.measure)
            #expect(cache.count <= 4)
        }
        #expect(cache.capacity == 4)
        #expect(cache.count > 0)
        #expect(TextInkCache().capacity == TextInkCache.defaultCapacity)

        let recent = RecordingInk()
        let small = TextInkCache(capacity: 4, fontGeneration: { 0 })
        for text in ["a", "b", "c", "d", "a", "e"] {
            _ = small.inkBounds(of: Self.key(text), measure: recent.measure)
        }
        #expect(recent.count == 5, "a repeat of a was laid out again")
        _ = small.inkBounds(of: Self.key("a"), measure: recent.measure)
        #expect(recent.count == 5, "the recently used a was forgotten")
        _ = small.inkBounds(of: Self.key("b"), measure: recent.measure)
        #expect(recent.count == 6, "b, the least recently used, was kept past the capacity")
    }

    @Test("textInkBounds answers from the cache what a fresh layout answers")
    func textInkBoundsMatchesALayout() throws {
        let json = """
        {"version": "2.19", "children": [{"type": "text", "id": "t", "x": 0, "y": 0, "width": 30,
          "textGrowth": "fixed-width", "content": "An unbreakable-word and more", "fontFamily": "Helvetica",
          "fontSize": 16, "fontStyle": "italic"}]}
        """
        let document = try PenParser.parse(Data(json.utf8))
        let node = try #require(document.children.first)
        let rect = try #require(PenLayoutEngine.layout(document)["t"])
        let box = PenRect(x: 0, y: 0, width: rect.width, height: rect.height)
        let layout = try #require(PenTextLayout(node, box: CGSize(width: box.width, height: box.height)))
        let fresh = try #require(layout.inkBounds)

        let cache = TextInkCache(fontGeneration: { 0 })
        let counter = CostCounter()
        let (first, second) = TextInkCache.$current.withValue(cache) {
            CostCounter.$current.withValue(counter) {
                (PenLayoutEngine.textInkBounds(of: node, box: box), PenLayoutEngine.textInkBounds(of: node, box: box))
            }
        }

        let expected = PenRect(
            x: Double(fresh.minX), y: Double(fresh.minY), width: Double(fresh.width), height: Double(fresh.height)
        )
        #expect(first == expected)
        #expect(second == expected)
        #expect(counter.count(of: .textInkLookup) == 2)
        #expect(counter.count(of: .textInkLayout) == 1)
    }
}
