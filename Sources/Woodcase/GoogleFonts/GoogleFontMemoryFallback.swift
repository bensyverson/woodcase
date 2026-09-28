//
//  GoogleFontMemoryFallback.swift
//  Woodcase
//

import Foundation
import os

/// Holds downloaded font data for the life of the process when ``GoogleFontCache``
/// cannot write it to disk.
///
/// A resolver that cannot persist a download would otherwise re-download it every time
/// a *different* ``GoogleFontResolver`` instance resolves the same family —
/// `GoogleFontResolver/shared` never needs to, because its own `resolvedFamilies` set
/// already remembers a family for the resolver's own lifetime, but a second instance (a
/// test, or a host embedding its own resolver) has no such memory and no working disk
/// cache to fall back to either. This is the same shape as ``PenFontRegistry`` and
/// ``FontResolutionCache``: one process-wide store, guarded by a lock, that nothing on
/// disk backs.
enum GoogleFontMemoryFallback {
    /// The store, keyed by the cache's root directory, the family and the file name.
    ///
    /// Keying on the family alone would let two *unrelated* caches — different root
    /// directories, one broken and one fine — share a fallback entry just because a
    /// test (or a host embedding more than one resolver) happens to resolve the same
    /// family name against both. Root-scoping is also what makes the family-name
    /// coincidence across this file's own tests harmless without every test having to
    /// call ``reset()``. The file name is there because a family is several files — a
    /// face each, and its METADATA.pb.
    private static let state = OSAllocatedUnfairLock<[Key: [String: Data]]>(initialState: [:])

    private struct Key: Hashable {
        let root: String
        let family: String
    }

    /// Stores `data` as `family`'s file `filename`, scoped to `rootDirectory` — the cache
    /// whose write failed — and normalized the way ``GoogleFontCache`` normalizes its
    /// directory names, so a lookup does not care how the family was spelled.
    ///
    /// - Parameters:
    ///   - data: The downloaded bytes.
    ///   - rootDirectory: The cache's root directory, from ``GoogleFontCache/rootDirectory``.
    ///   - family: The font family name, in its display spelling.
    ///   - filename: The file's name in the google/fonts repository.
    static func store(_ data: Data, rootDirectory: URL, family: String, filename: String) {
        state.withLock { $0[key(rootDirectory: rootDirectory, family: family), default: [:]][filename] = data }
    }

    /// The files previously stored for `family` under `rootDirectory`, by file name;
    /// empty if nothing was.
    ///
    /// - Parameters:
    ///   - rootDirectory: The cache's root directory, from ``GoogleFontCache/rootDirectory``.
    ///   - family: The font family name, in its display spelling.
    static func files(rootDirectory: URL, family: String) -> [String: Data] {
        state.withLock { $0[key(rootDirectory: rootDirectory, family: family)] ?? [:] }
    }

    /// Clears every entry. Intended for tests that want a clean slate regardless of
    /// which root directories they used.
    static func reset() {
        state.withLock { $0.removeAll() }
    }

    private static func key(rootDirectory: URL, family: String) -> Key {
        Key(
            root: rootDirectory.standardizedFileURL.path,
            family: GoogleFontCache.directoryName(for: family)
        )
    }
}
