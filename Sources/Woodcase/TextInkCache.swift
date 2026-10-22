//
//  TextInkCache.swift
//  Woodcase
//

import Foundation
import Synchronization

/// Remembers the glyph ink of the texts ``PenLayoutEngine/textInkBounds(of:box:)`` has
/// measured, so an unchanged text is set and outlined once per process, not once per
/// painted-extent pass.
///
/// Setting a text and walking its glyph outlines is nearly all a painted-extent pass costs
/// on a board of texts, and an editor runs one pass for its renderer and one for its hit
/// shapes after every edit — over mostly the same texts. So the ink lives here, shared by
/// every pass of the process: ``shared``, which ``current`` names unless a test installs
/// its own.
///
/// ## The key
///
/// Everything ``PenTextLayout`` reads to place the ink (``Key``): the text, its style, its
/// styled runs with their colors taken out — a color never moves a glyph — and its box's
/// width and height, which set the wrapping and the vertical alignment. Nothing else about
/// the node reaches the layout, so nothing else can change the ink — except the font set.
///
/// ## The font set
///
/// The fonts Core Text knows grow while a process runs (``PenFontRegistry``), and a text
/// set before its family registered is set in a fallback. So every ink belongs to one
/// ``PenFontRegistry/generation``: the first lookup after it moves discards them all, and
/// an ink measured across a registration is answered but never kept — the rule
/// ``TextSizeCache`` keeps for sizes.
///
/// ## The lock
///
/// The cache's lock is a leaf: held only around ``FontGenerationStore``'s dictionary
/// reads and writes, which call nothing else, and released before a measurement starts.
/// The measurement — a Core Text layout, which waits for ``FontRegistryGate``
/// (`project/2026-10-20-fontd-wedge-and-the-layout-gate.md`) — runs between the lookup
/// and the insert with no lock of the cache's held, so the two locks never nest, and a
/// lookup on another thread never queues behind a layout queued behind the gate
/// (`TextInkCacheGateTests`). Two threads missing the same text at once both measure it;
/// the second insert overwrites the first with the same ink.
///
/// ## The bound
///
/// At most ``capacity`` inks (``defaultCapacity`` unless its maker says otherwise), the
/// least recently used forgotten first, by the two-generation turn ``TextSizeCache``
/// describes.
///
/// `package`, not internal, so `WoodcaseBench` can install a cache that keeps no ink and
/// time a painted-extent pass without one; nothing outside the package sees it.
package final class TextInkCache: Sendable {
    /// How many inks a cache holds unless its maker says otherwise: more texts than a
    /// large board shows at several widths, at a few megabytes.
    package static let defaultCapacity = 20000

    /// The process's cache, which every painted-extent pass shares.
    static let shared = TextInkCache()

    /// The cache ``PenLayoutEngine/textInkBounds(of:box:)`` reads: ``shared``, unless a
    /// test installs its own for the work it runs.
    @TaskLocal package static var current: TextInkCache = shared

    /// Everything a text's ink depends on but the font set.
    struct Key: Friendly {
        /// The text.
        let text: String
        /// Its style.
        let style: PenTextStyle
        /// Its styled runs, without their fills.
        let runs: [PenTextRun]
        /// Its box's width, which it wraps at.
        let width: Double
        /// Its box's height, which vertical alignment places the block in.
        let height: Double

        /// Creates a key, taking every run's fill out.
        ///
        /// - Parameters:
        ///   - text: The text.
        ///   - style: Its style.
        ///   - runs: Its styled runs.
        ///   - width: Its box's width.
        ///   - height: Its box's height.
        init(text: String, style: PenTextStyle, runs: [PenTextRun], width: Double, height: Double) {
            self.text = text
            self.style = style
            self.runs = runs.map { run in
                var uncolored = run
                uncolored.fill = nil
                return uncolored
            }
            self.width = width
            self.height = height
        }
    }

    /// A measured ink: its bounds, or `nil` for a text with no ink — kept too, since an
    /// answer of none costs a layout as well.
    private struct Ink: Friendly {
        /// The bounds.
        let bounds: PenRect?
    }

    /// Creates an empty cache.
    ///
    /// - Parameters:
    ///   - capacity: The most inks the cache holds; at least 2.
    ///   - fontGeneration: Reads the font set's generation. Production reads
    ///     ``PenFontRegistry/generation``; a test passes its own so a registration by
    ///     another suite cannot move it.
    package init(
        capacity: Int = TextInkCache.defaultCapacity,
        fontGeneration: @escaping @Sendable () -> Int = { PenFontRegistry.generation }
    ) {
        self.capacity = capacity
        generation = fontGeneration
        state = Mutex(FontGenerationStore(capacity: capacity, fontGeneration: fontGeneration()))
    }

    /// The most inks the cache holds.
    let capacity: Int

    /// Reads the font set's generation.
    private let generation: @Sendable () -> Int

    /// The inks, behind the lock.
    private let state: Mutex<FontGenerationStore<Key, Ink>>

    /// How many inks the cache holds now; never more than ``capacity``.
    var count: Int {
        state.withLock { $0.count }
    }

    /// How many inks were measured, for the tests that prove one was reused.
    var measuredCount: Int {
        state.withLock { $0.measured }
    }

    /// A text's ink: the one kept for its key in the current font set, or `measure`'s
    /// answer, kept when the font set stood still while it ran.
    ///
    /// - Parameters:
    ///   - key: The text's key.
    ///   - measure: Sets the text and answers its ink; run outside the lock.
    /// - Returns: The ink's bounds, or `nil` when the text has none.
    func inkBounds(of key: Key, measure: (Key) -> PenRect?) -> PenRect? {
        let before = generation()
        if let hit = state.withLock({ $0.value(for: key, at: before) }) { return hit.bounds }

        let bounds = measure(key)
        let after = generation()
        state.withLock { $0.keep(Ink(bounds: bounds), for: key, measuredFrom: before, to: after) }
        return bounds
    }
}
