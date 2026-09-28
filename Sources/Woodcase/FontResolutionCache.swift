//
//  FontResolutionCache.swift
//  Woodcase
//

import CoreText
import Foundation

/// Process-wide cache for ``PenTextMeasurer/resolveFont(family:size:weight:style:)``
/// results and the result of ``PenTextMeasurer/hasWeightAxis(_:)``.
///
/// Font resolution is hot in two places:
///
/// 1. Every text node goes through `resolveFont`, which builds a
///    `CTFontDescriptor` and a `CTFont` from scratch.
/// 2. Inside `resolveFont`, `hasWeightAxis` calls `CTFontCopyVariationAxes`,
///    which in turn reads the font's `fvar` table via `CGFontCopyTableForTag`.
///    Time Profiler attributes a large share of text rasterization to those
///    two calls.
///
/// A resolution is only meaningful for the set of fonts Core Text knew about
/// when it ran, and that set grows while the process runs — see
/// ``PenFontRegistry``. Every entry here therefore belongs to a single
/// registration generation, and the whole cache is discarded the first time it
/// is touched after a registration. Without that, a lookup made before a font
/// was registered would pin the fallback for the rest of the process.
///
/// This cache is shared across all threads because `CTFont` is immutable and
/// thread-safe; the lock guards the backing dictionaries only.
final class FontResolutionCache: @unchecked Sendable {
    struct Key: Hashable {
        let family: String
        let size: Double
        let weight: String
        let style: String
    }

    private let lock = NSLock()
    private var fonts: [Key: CTFont] = [:]
    private var weightAxis: [String: Bool] = [:]

    /// The registration generation every current entry was resolved under.
    private var generation: Int = PenFontRegistry.generation

    private(set) var fontComputeCount: Int = 0
    private(set) var weightAxisComputeCount: Int = 0

    func font(for key: Key) -> CTFont? {
        lock.lock()
        defer { lock.unlock() }
        discardIfStale()
        return fonts[key]
    }

    /// Stores a resolved font, unless fonts were registered while it was being resolved.
    ///
    /// - Parameter resolvedGeneration: ``PenFontRegistry/generation`` as read
    ///   *before* the resolution ran. A resolution that straddles a
    ///   registration describes the older font set and is dropped rather than
    ///   stored, which closes the window a plain "invalidate on registration"
    ///   check would leave open.
    func setFont(_ font: CTFont, for key: Key, resolvedAt resolvedGeneration: Int) {
        lock.lock()
        defer { lock.unlock() }
        discardIfStale()
        guard resolvedGeneration == generation else { return }
        fonts[key] = font
        fontComputeCount += 1
    }

    func hasWeightAxis(forPostScriptName name: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        discardIfStale()
        return weightAxis[name]
    }

    /// Stores a weight-axis answer, unless fonts were registered while it was being computed.
    ///
    /// - Parameter resolvedGeneration: ``PenFontRegistry/generation`` as read
    ///   before the font tables were interrogated.
    func setHasWeightAxis(
        _ value: Bool,
        forPostScriptName name: String,
        resolvedAt resolvedGeneration: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        discardIfStale()
        guard resolvedGeneration == generation else { return }
        weightAxis[name] = value
        weightAxisComputeCount += 1
    }

    /// Clears all cached entries. Intended for tests.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        fonts.removeAll()
        weightAxis.removeAll()
        generation = PenFontRegistry.generation
        fontComputeCount = 0
        weightAxisComputeCount = 0
    }

    /// Drops every entry if fonts have been registered since they were resolved.
    ///
    /// Must be called with ``lock`` held.
    private func discardIfStale() {
        let current = PenFontRegistry.generation
        guard current != generation else { return }
        fonts.removeAll()
        weightAxis.removeAll()
        generation = current
    }
}
