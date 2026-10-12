//
//  TextSizeCache.swift
//  Woodcase
//

import Foundation
import Synchronization

/// Remembers the size of the texts a ``TextMeasurer`` has measured, so the settles of
/// one run — or the passes of one ``PenLayoutState`` — typeset each text once.
///
/// Laying a document out measures every text in it, and the settles of one run measure
/// mostly the same texts: a write's overlap check measures the roots before the edit and
/// after it, and a script re-settles a root after every write to it. Core Text
/// typesetting is most of that work, so ``measurer`` answers a text it has seen from
/// memory and passes only the new ones to the measurer behind it.
///
/// ## The key
///
/// The ``PenTextMeasureRequest`` itself — everything the measurer is given: the text, the
/// family, size, weight and style, the letter spacing, the line height, the wrapping width
/// and the styled runs — with the runs' colors taken out (``PenTextMeasureRequest/ignoringColor``),
/// since a color never changes a size. A ``TextMeasurer`` sees
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
/// `FontResolutionCache` keeps for the faces themselves.
///
/// ## How long one lives, and how big it grows
///
/// As long as what it serves: a script run (the scripting host's settled-tree cache owns
/// one), one write's pair of overlap measurements (`RootOverlap.Baseline`), or a
/// ``PenLayoutState`` — an editor's layout, which lives as long as the document is open.
/// So it is bounded: it holds at most ``capacity`` sizes (``defaultCapacity`` unless the
/// owner says otherwise) and forgets the least recently used first.
///
/// The eviction is two generations rather than an exact list: new sizes go into a young
/// generation, a size read from the old one is moved into the young one, and when the
/// young generation holds half the capacity the old one is dropped and the young one
/// takes its place. Every operation is a dictionary lookup, a size used since the last
/// turn always survives the next, and the cache never holds more than ``capacity``.
///
/// A class, not a `Friendly` value: it is shared state behind a lock, handed to every
/// settle of a run by reference. A copy of a ``PenLayoutState`` shares its owner's,
/// which is sound: a size is a function of its request and the font set alone.
public final class TextSizeCache: Sendable {
    /// How many sizes a cache holds unless its owner says otherwise: more texts than a
    /// large board shows at several widths, at a few megabytes.
    public static let defaultCapacity = 20000

    /// A measured size.
    struct Size: Friendly {
        /// The width.
        let width: Double
        /// The height.
        let height: Double
    }

    /// The sizes, and the font set they were measured in.
    struct State {
        /// The ``PenFontRegistry/generation`` every size was measured at.
        var generation: Int
        /// The sizes stored or read since the last turn.
        var young: [PenTextMeasureRequest: Size] = [:]
        /// The sizes of the generation before, dropped at the next turn.
        var old: [PenTextMeasureRequest: Size] = [:]
        /// How many texts reached the base measurer.
        var measured = 0

        /// Forgets every size.
        mutating func removeAll() {
            young.removeAll(keepingCapacity: true)
            old.removeAll()
        }

        /// The size kept for a request, moved into the young generation when it was old.
        mutating func read(_ key: PenTextMeasureRequest, generationSize: Int) -> Size? {
            if let size = young[key] { return size }
            guard let size = old.removeValue(forKey: key) else { return nil }
            store(size, for: key, generationSize: generationSize)
            return size
        }

        /// Keeps a size in the young generation, turning the generations first when it
        /// is full.
        mutating func store(_ size: Size, for key: PenTextMeasureRequest, generationSize: Int) {
            if young[key] == nil, young.count >= generationSize {
                old = young
                young = [:]
                young.reserveCapacity(generationSize)
            }
            young[key] = size
        }
    }

    /// Creates an empty cache in front of a measurer.
    ///
    /// - Parameters:
    ///   - base: The measurer that answers a text the cache has not seen.
    ///   - capacity: The most sizes the cache holds; at least 2.
    ///   - fontGeneration: Reads the font set's generation. Production reads
    ///     ``PenFontRegistry/generation``; a test passes its own so a registration by
    ///     another suite cannot move it.
    public init(
        measuring base: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer,
        capacity: Int = TextSizeCache.defaultCapacity,
        fontGeneration: @escaping @Sendable () -> Int = { PenFontRegistry.generation }
    ) {
        precondition(capacity >= 2, "a text size cache holds at least two sizes")
        self.base = base
        self.capacity = capacity
        generationSize = capacity / 2
        generation = fontGeneration
        state = Mutex(State(generation: fontGeneration()))
    }

    /// The most sizes the cache holds.
    public let capacity: Int

    /// The most sizes one generation holds: half the capacity.
    private let generationSize: Int

    /// The measurer behind the cache.
    private let base: TextMeasurer

    /// Reads the font set's generation.
    private let generation: @Sendable () -> Int

    /// The sizes, behind the lock.
    private let state: Mutex<State>

    /// The font set's generation, as the cache reads it — ``PenFontRegistry/generation``
    /// unless the cache was made with another source.
    public var fontGeneration: Int {
        generation()
    }

    /// How many sizes the cache holds now; never more than ``capacity``.
    public var count: Int {
        state.withLock { $0.young.count + $0.old.count }
    }

    /// How many texts the base measurer has been asked for, for the tests that prove a
    /// size was reused.
    package var measuredCount: Int {
        state.withLock { $0.measured }
    }

    /// A measurer that answers from the cache, and measures through the base measurer
    /// only a text it has not seen in the current font set.
    public var measurer: TextMeasurer {
        { [self] request in
            let key = request.ignoringColor
            let before = generation()
            let hit: Size? = state.withLock { state in
                if state.generation != before {
                    state.removeAll()
                    state.generation = before
                }
                return state.read(key, generationSize: generationSize)
            }
            if let hit { return (hit.width, hit.height) }

            let measured = base(request)
            let after = generation()
            state.withLock { state in
                state.measured += 1
                guard after == before, state.generation == before else { return }
                state.store(Size(width: measured.width, height: measured.height), for: key, generationSize: generationSize)
            }
            return measured
        }
    }
}
