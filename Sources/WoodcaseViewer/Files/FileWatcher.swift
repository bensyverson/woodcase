//
//  FileWatcher.swift
//  WoodcaseViewer
//

import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Watches .pen files for edits and reports each one once.
///
/// ## Why it re-arms
///
/// ``PenFileTransaction`` commits by writing a temporary neighbour and `rename(2)`-ing
/// it over the original — the only way to leave a reader either the whole old file or
/// the whole new one. That means the file descriptor a watcher holds stops being the
/// file at that path: it sees `.rename`/`.delete` and then goes quiet forever, watching
/// an unlinked inode nobody will write to again. Any editor worth using
/// writes the same way, so a watcher that does not re-open the path reports the *first*
/// edit and no others — which looks exactly like a viewer that has gone stale.
///
/// So every event cancels the source, re-opens the path, and arms a new one.
///
/// ## Why it debounces
///
/// One save is several events — a write, an extend, an attribute change, a rename — and
/// re-rendering an artboard for each is wasted work on a document that is not finished
/// changing. Events for one file inside ``debounce`` collapse into one report.
///
/// ```swift
/// let watcher = FileWatcher()
/// let changes = await watcher.changes
/// await watcher.watch(files)
/// for await url in changes { await coordinator.fileChanged(url) }
/// ```
public actor FileWatcher {
    /// Creates a watcher.
    ///
    /// - Parameter debounce: How long to gather events for one file before reporting.
    public init(debounce: Duration = .milliseconds(100)) {
        self.debounce = debounce
        var escaping: AsyncStream<URL>.Continuation!
        changes = AsyncStream { escaping = $0 }
        continuation = escaping
    }

    /// How long events for one file are gathered before it is reported changed.
    public let debounce: Duration

    /// The files that changed, one report per settled edit.
    ///
    /// The stream finishes when ``stop()`` is called, which is what lets the task
    /// consuming it end rather than outlive the server.
    public nonisolated let changes: AsyncStream<URL>

    /// Where reports are written.
    private nonisolated let continuation: AsyncStream<URL>.Continuation

    /// The queue the Dispatch sources fire on.
    private let queue = DispatchQueue(label: "dev.woodcase.viewer.filewatcher")

    /// The live source per watched path.
    private var sources: [String: any DispatchSourceFileSystemObject] = [:]

    /// Paths with a report already scheduled, so a burst reports once.
    private var settling: Set<String> = []

    /// Whether ``stop()`` has run.
    private var isStopped = false

    /// How many files are being watched.
    public var watchedCount: Int {
        sources.count
    }

    /// Starts watching files, in addition to any already watched.
    ///
    /// A path that does not exist is skipped rather than failing the call: the caller
    /// gave a list of files to serve, and one of them having been deleted is not a
    /// reason for the other four to go unwatched. It is reported by ``watchedCount``
    /// being lower than the list.
    ///
    /// - Parameter urls: The files to watch.
    public func watch(_ urls: [URL]) {
        guard !isStopped else { return }
        for url in urls {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard sources[path] == nil else { continue }
            arm(path)
        }
    }

    /// Stops watching everything and finishes ``changes``.
    public func stop() {
        isStopped = true
        for source in sources.values {
            source.cancel()
        }
        sources.removeAll()
        settling.removeAll()
        continuation.finish()
    }

    // MARK: - Private

    /// Opens a path and arms a source on it.
    private func arm(_ path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.fired(path) }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        sources[path] = source
        source.resume()
    }

    /// Handles one event: re-arm at once, then report once the burst settles.
    private func fired(_ path: String) {
        guard !isStopped else { return }

        // Re-arm before anything else. The descriptor that fired may be looking at an
        // inode that has just been renamed away, and every edit after this one would be
        // invisible if the new one were armed only after the debounce.
        sources.removeValue(forKey: path)?.cancel()
        arm(path)

        guard !settling.contains(path) else { return }
        settling.insert(path)
        Task { [debounce] in
            try? await Task.sleep(for: debounce)
            self.report(path)
        }
    }

    /// Reports a settled path.
    private func report(_ path: String) {
        settling.remove(path)
        guard !isStopped else { return }
        continuation.yield(URL(fileURLWithPath: path))
    }
}
