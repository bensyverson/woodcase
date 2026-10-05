//
//  FileWatcher.swift
//  Woodcase
//

import Foundation

/// Watches .pen files for edits and reports each one once.
///
/// ## Why it survives replacement
///
/// ``PenFileTransaction`` commits by writing a temporary neighbor and `rename(2)`-ing
/// it over the original — the only way to leave a reader either the whole old file or
/// the whole new one. A watcher holding a descriptor on the file is then watching an
/// unlinked inode nobody will write to again, which looks exactly like a viewer that has
/// gone stale. And if the path is deleted and recreated by another tool there is, for a
/// moment, no file to re-open at all.
///
/// So each ``Backend`` watches the *directory* as well as the file (or, for polling,
/// compares what `stat` says): a path that is missing stays watched, and is reported when
/// it comes back.
///
/// ## Why it debounces
///
/// One save is several events — a write, an extend, an attribute change, a rename — and
/// re-rendering an artboard for each is wasted work on a document that is not finished
/// changing. Events for one file inside ``debounce`` collapse into one report.
///
/// ```swift
/// let watcher = FileWatcher()
/// let changes = watcher.changes
/// await watcher.watch(files)
/// for await url in changes { await coordinator.fileChanged(url) }
/// ```
///
/// A consumer that polls instead of awaiting — a pull loop with no task of its own —
/// calls ``drain()``; use one of the two, since a settled report is both yielded and held
/// for the next drain.
public actor FileWatcher {
    /// Creates a watcher.
    ///
    /// - Parameters:
    ///   - debounce: How long to gather events for one file before reporting.
    ///   - backend: How changes are noticed. Defaults to the platform's native API.
    public init(debounce: Duration = .milliseconds(100), backend: Backend = .native) {
        self.debounce = debounce
        backendKind = backend
        var escaping: AsyncStream<URL>.Continuation!
        changes = AsyncStream { escaping = $0 }
        continuation = escaping
    }

    deinit {
        // The backend cancels its sources when released; the stream must end too, or a
        // consumer awaiting it would outlive the watcher.
        continuation.finish()
    }

    /// How long events for one file are gathered before it is reported changed.
    public let debounce: Duration

    /// The files that changed, one report per settled edit.
    ///
    /// The stream finishes when ``stop()`` is called, which is what lets the task
    /// consuming it end rather than outlive the server.
    public nonisolated let changes: AsyncStream<URL>

    /// How many files are being watched, counting ones that currently do not exist.
    public var watchedCount: Int {
        backend?.watchedCount ?? 0
    }

    /// Starts watching files, in addition to any already watched.
    ///
    /// A path that does not exist yet is watched and reported when it appears. A path
    /// whose directory does not exist cannot be watched and is skipped rather than
    /// failing the call: the caller gave a list of files to serve, and one of them having
    /// been deleted is not a reason for the other four to go unwatched. It is reported by
    /// ``watchedCount`` being lower than the list.
    ///
    /// - Parameter urls: The files to watch: bare `.pen` files, or `.umbra` bundles,
    ///   whose `document.pen` is watched and reported (``PenLocation``).
    public func watch(_ urls: [URL]) {
        guard !isStopped else { return }
        let backend = activeBackend()
        for url in urls {
            // A bundle is watched through its document.pen, the file a write replaces.
            let path = PenLocation(url).document.standardizedFileURL.resolvingSymlinksInPath().path
            guard !watched.contains(path) else { continue }
            if backend.watch(path: path) {
                watched.insert(path)
            }
        }
    }

    /// The files reported since the last call, in no particular order.
    ///
    /// Pull-mode access to the same settled reports ``changes`` yields.
    ///
    /// - Returns: Each changed file once.
    public func drain() -> [URL] {
        defer { drained.removeAll() }
        return drained.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Stops watching everything and finishes ``changes``.
    public func stop() {
        isStopped = true
        backend?.stop()
        backend = nil
        watched.removeAll()
        settling.removeAll()
        drained.removeAll()
        continuation.finish()
    }

    // MARK: - Private

    /// The backend chosen at creation, made on first ``watch(_:)``.
    private let backendKind: Backend
    /// Where reports are written.
    private nonisolated let continuation: AsyncStream<URL>.Continuation

    /// Created on first use, once `self` can be captured.
    private var backend: (any FileWatchBackend)?

    /// Canonical paths handed to the backend and accepted.
    private var watched: Set<String> = []

    /// Paths with a report already scheduled, so a burst reports once.
    private var settling: Set<String> = []

    /// Settled reports not yet drained.
    private var drained: Set<String> = []

    /// Whether ``stop()`` has run.
    private var isStopped = false

    /// The backend, made on first use so its handler can capture `self` weakly.
    private func activeBackend() -> any FileWatchBackend {
        if let backend { return backend }
        let made = FileWatchBackendFactory.make(backendKind) { [weak self] path in
            Task { await self?.fired(path) }
        }
        backend = made
        return made
    }

    /// Handles one backend event: report once the burst settles.
    private func fired(_ path: String) {
        guard !isStopped, !settling.contains(path) else { return }
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
        drained.insert(path)
        continuation.yield(URL(fileURLWithPath: path))
    }
}
