//
//  FileWatchBackend.swift
//  Woodcase
//

import Foundation

/// One way of noticing that a file changed.
///
/// A backend only *notices*: it calls its `onEvent` handler with the path, possibly
/// several times for one save, and ``FileWatcher`` debounces and reports. Every backend
/// reports a path that is deleted and later recreated — the case a descriptor-only
/// watcher loses, because the descriptor follows the unlinked inode.
protocol FileWatchBackend: Sendable {
    /// Starts watching a path.
    ///
    /// A path that does not exist yet is watched, and reported when it appears. A path
    /// whose parent directory cannot be watched is refused.
    ///
    /// - Parameter path: A canonical absolute path.
    /// - Returns: Whether the path is now watched.
    func watch(path: String) -> Bool

    /// How many paths are watched, including ones that currently do not exist.
    var watchedCount: Int { get }

    /// Cancels every source. The handler is not called afterwards.
    func stop()
}

extension FileWatchBackend {
    /// The directory a path lives in.
    static func parentDirectory(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }
}
