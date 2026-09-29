//
//  PenTextMeasurerFontCacheTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Each test counts hits and misses on a cache of its own — but a cache of one's own is
/// not enough on its own.
///
/// ``PenFontRegistry/generation`` is process-wide, and a registration by *any* suite
/// discards every cache in the process, including this one, mid-test. That drops the
/// very store the accounting is counting, and turns an exact count into a coin flip:
/// `resolveFont computes new entry when key differs` reported 2 of 3 once in ten full
/// runs. So every case here runs its window again if a registration landed inside it —
/// which is what makes the number a measurement of the cache rather than of the
/// neighbors.
@Suite("PenTextMeasurer Font Cache")
struct PenTextMeasurerFontCacheTests {
    /// How many times a window is retried before its count is asserted anyway.
    private static let attempts = 5

    /// Runs `body` against a fresh cache, retrying while a font registration lands
    /// inside the window.
    ///
    /// Every attempt is built and returned on the spot. Holding the running answer in
    /// a *declared-but-unassigned* `var` across the loop instead — the obvious way to
    /// write this — is miscompiled by Swift 6.3.3 at `-O` without whole-module
    /// optimization, which is how the release test build compiles this file: the
    /// destroy of the previous, not-yet-existent tuple is emitted unguarded, so the
    /// first iteration calls `swift_release` on whatever the preceding call left in
    /// `x0` — here the freshly resolved `CTFont`, whose CoreFoundation header it then
    /// corrupts. See `project/2026-08-30-release-only-ctfont-sigtrap.md`;
    /// `scripts/swift-di-miscompile` says whether the toolchain still does it.
    ///
    /// - Parameter body: The resolutions to count. It may run more than once.
    /// - Returns: The cache the last attempt filled, and whatever `body` returned.
    private static func undisturbed<T>(
        _ body: (FontResolutionCache) -> T
    ) -> (cache: FontResolutionCache, value: T) {
        for _ in 1 ..< attempts {
            let cache = FontResolutionCache()
            let before = PenFontRegistry.generation
            let value = body(cache)
            if PenFontRegistry.generation == before { return (cache, value) }
        }
        // Out of retries: report the last window's count and let the case judge it.
        let cache = FontResolutionCache()
        return (cache, body(cache))
    }

    @Test("resolveFont returns identical CTFont for repeated identical key")
    func resolveFontReturnsCachedInstance() {
        let (cache, fonts) = Self.undisturbed { cache in
            (
                PenTextMeasurer.resolveFont(
                    family: "Helvetica", size: 14, weight: "normal", style: "normal", cache: cache
                ),
                PenTextMeasurer.resolveFont(
                    family: "Helvetica", size: 14, weight: "normal", style: "normal", cache: cache
                )
            )
        }

        // CTFont is a class type — identity check verifies cache hit.
        #expect(fonts.0 === fonts.1)
        #expect(cache.fontComputeCount == 1)
    }

    @Test("resolveFont computes new entry when key differs")
    func resolveFontDistinguishesKeys() {
        let (cache, _) = Self.undisturbed { cache in
            _ = PenTextMeasurer.resolveFont(
                family: "Helvetica", size: 14, weight: "normal", style: "normal", cache: cache
            )
            _ = PenTextMeasurer.resolveFont(
                family: "Helvetica", size: 18, weight: "normal", style: "normal", cache: cache
            )
            _ = PenTextMeasurer.resolveFont(
                family: "Helvetica", size: 14, weight: "bold", style: "normal", cache: cache
            )
        }

        #expect(cache.fontComputeCount == 3)
    }

    @Test("hasWeightAxis is computed once per PostScript name")
    func hasWeightAxisMemoized() {
        let (cache, _) = Self.undisturbed { cache in
            // Trigger the path that consults hasWeightAxis by resolving a font
            // across several sizes. Same base family → same PS name once the
            // descriptor resolves.
            for size in [12.0, 14.0, 16.0, 18.0, 20.0] {
                _ = PenTextMeasurer.resolveFont(
                    family: PenTextMeasurer.defaultFontFamily,
                    size: size, weight: "normal", style: "normal", cache: cache
                )
            }
        }

        // Even though we resolved five distinct font keys, the weight-axis
        // interrogation should fire at most a handful of times (one per
        // unique PostScript name returned by the system). For a stable
        // family like "SF Pro" that is a single PS name, we expect 1.
        #expect(cache.weightAxisComputeCount <= 2)
    }
}
