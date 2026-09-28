//
//  TextSizeCache.swift
//  Woodcase
//

import Foundation
import Synchronization

/// Remembers the size of every text a ``TextMeasurer`` has measured, so the settles of
/// one run typeset each text once.
///
/// Laying a document out measures every text in it, and the settles of one run measure
/// mostly the same texts: a write's overlap check measures the roots before the edit and
/// after it, and a script re-settles a root after every write to it. Core Text
/// typesetting is most of that work, so ``measurer`` answers a text it has seen from
/// memory and passes only the new ones to the measurer behind it.
///
/// ## The key
///
/// Everything the measurer is given: the text, the family, size, weight and style, the
/// letter spacing, the line height and the wrapping width. A ``TextMeasurer`` sees
/// nothing else about the node, so nothing else can change its answer — except the font
/// set, which is not an argument.
///
/// ## The font set
///
/// Core Text's registered fonts are process-global and grow while the process runs
/// (``PenFontRegistry``): a family that becomes available between two settles measures
/// differently in the second. So every size belongs to one ``PenFontRegistry/generation``.
/// The first measurement after the generation moves discards them all, and a size whose
/// measurement straddled a registration is returned but never kept — the same rule
/// ``FontResolutionCache`` keeps for the faces themselves.
///
/// ## How long one lives
///
/// As long as the run it serves, and no longer: a script run (the scripting host's
/// settled-tree cache owns one), or one write's pair of overlap measurements
/// (``RootOverlap/Baseline``). It is not process-wide, because nothing bounds what a
/// long-lived process would measure.
///
/// A class, not a `Friendly` value: it is shared state behind a lock, handed to every
/// settle of a run by reference.
package final class TextSizeCache: Sendable {
    /// Everything a ``TextMeasurer`` is given, and so everything that decides a size in
    /// one font set.
    struct Key: Friendly {
        /// The string.
        let text: String
        /// The font family, or `nil` for the default.
        let family: String?
        /// The font size, or `nil` for the default.
        let size: Double?
        /// The CSS-style weight, or `nil` for normal.
        let weight: String?
        /// The CSS-style style, or `nil` for normal.
        let style: String?
        /// The letter spacing, or `nil` for none.
        let letterSpacing: Double?
        /// The line height multiplier, or `nil` for the font's own.
        let lineHeight: Double?
        /// The wrapping width, or `nil` for one line.
        let maxWidth: Double?
    }

    /// A measured size.
    struct Size: Friendly {
        /// The width.
        let width: Double
        /// The height.
        let height: Double
    }

    /// The sizes, and the font set they were measured in.
    struct State {
        /// The ``PenFontRegistry/generation`` every size in ``sizes`` was measured at.
        var generation: Int
        /// The sizes measured so far.
        var sizes: [Key: Size] = [:]
        /// How many texts reached the base measurer.
        var measured = 0
    }

    /// Creates an empty cache in front of a measurer.
    ///
    /// - Parameters:
    ///   - base: The measurer that answers a text the cache has not seen.
    ///   - fontGeneration: Reads the font set's generation. Production reads
    ///     ``PenFontRegistry/generation``; a test passes its own so a registration by
    ///     another suite cannot move it.
    package init(
        measuring base: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer,
        fontGeneration: @escaping @Sendable () -> Int = { PenFontRegistry.generation }
    ) {
        self.base = base
        generation = fontGeneration
        state = Mutex(State(generation: fontGeneration()))
    }

    /// The measurer behind the cache.
    private let base: TextMeasurer

    /// Reads the font set's generation.
    private let generation: @Sendable () -> Int

    /// The sizes, behind the lock.
    private let state: Mutex<State>

    /// The font set's generation, as the cache reads it.
    package var fontGeneration: Int {
        generation()
    }

    /// How many texts the base measurer has been asked for, for the tests that prove a
    /// size was reused.
    package var measuredCount: Int {
        state.withLock { $0.measured }
    }

    /// A measurer that answers from the cache, and measures through the base measurer
    /// only a text it has not seen in the current font set.
    package var measurer: TextMeasurer {
        { [self] text, family, size, weight, style, letterSpacing, lineHeight, maxWidth in
            let key = Key(
                text: text, family: family, size: size, weight: weight, style: style,
                letterSpacing: letterSpacing, lineHeight: lineHeight, maxWidth: maxWidth
            )
            let before = generation()
            let hit: Size? = state.withLock { state in
                if state.generation != before {
                    state.sizes.removeAll(keepingCapacity: true)
                    state.generation = before
                }
                return state.sizes[key]
            }
            if let hit { return (hit.width, hit.height) }

            let measured = base(text, family, size, weight, style, letterSpacing, lineHeight, maxWidth)
            let after = generation()
            state.withLock { state in
                state.measured += 1
                guard after == before, state.generation == before else { return }
                state.sizes[key] = Size(width: measured.width, height: measured.height)
            }
            return measured
        }
    }
}
