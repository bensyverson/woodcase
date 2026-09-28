//
//  RemoteImageMemoryFallback.swift
//  Woodcase
//

import Foundation
import os

/// Holds downloaded image bytes for the life of the process when ``RemoteImageCache``
/// cannot write them to disk.
///
/// The same shape, and for the same reason, as ``GoogleFontMemoryFallback``: without
/// it a resolver whose cache directory is unwritable would re-download the image every
/// time a *different* ``RemoteImageResolver`` instance asked for it, and — worse than
/// for fonts — the synchronous ``RemoteImageResolver/cachedImage(for:)`` on the render
/// path would find nothing at all, so the fill would draw blank despite a successful
/// download.
enum RemoteImageMemoryFallback {
    /// The store, keyed by both the cache's root directory and the URL.
    ///
    /// Root-scoped for the reason ``GoogleFontMemoryFallback`` is: two unrelated caches
    /// — one broken, one fine — must not share an entry just because the same URL was
    /// resolved against both, and scoping keeps a URL reused across tests from leaking
    /// between them without every test resetting a process-wide store.
    private static let state = OSAllocatedUnfairLock<[Key: Data]>(initialState: [:])

    private struct Key: Hashable {
        let root: String
        let url: String
    }

    /// Stores `data` for `urlString`, scoped to the cache whose write failed.
    ///
    /// - Parameters:
    ///   - data: The downloaded image bytes.
    ///   - rootDirectory: The cache's root directory, from ``RemoteImageCache/rootDirectory``.
    ///   - urlString: The image fill's URL.
    static func store(_ data: Data, rootDirectory: URL, urlString: String) {
        state.withLock { $0[key(rootDirectory: rootDirectory, urlString: urlString)] = data }
    }

    /// The data previously stored for `urlString` under `rootDirectory`, or `nil`.
    ///
    /// - Parameters:
    ///   - rootDirectory: The cache's root directory.
    ///   - urlString: The image fill's URL.
    /// - Returns: The stored bytes, or `nil` if nothing was stored.
    static func data(rootDirectory: URL, urlString: String) -> Data? {
        state.withLock { $0[key(rootDirectory: rootDirectory, urlString: urlString)] }
    }

    /// Clears every entry. Intended for tests that want a clean slate.
    static func reset() {
        state.withLock { $0.removeAll() }
    }

    private static func key(rootDirectory: URL, urlString: String) -> Key {
        Key(root: rootDirectory.standardizedFileURL.path, url: urlString)
    }
}
