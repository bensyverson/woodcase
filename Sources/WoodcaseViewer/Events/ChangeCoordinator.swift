//
//  ChangeCoordinator.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Turns two streams of raw signal — the file watcher and the activity log — into the
/// one `change` event the page acts on, and keeps presence current from the same log.
///
/// ## Why two sources
///
/// The **watcher** is the truth about the file: it fires for every write, including one
/// any editor made, which the log knows nothing about. The **log** is the
/// truth about who and what: identity, node ids, name paths. Neither alone is enough, so
/// the coordinator waits briefly for the log to explain a write it has already seen —
/// the log line is appended after the rename, so it arrives a beat later — and publishes
/// with whatever has arrived by then rather than holding the page back.
///
/// ``matchWindow`` is that wait. It is a bound on lateness, not a delay: a log event
/// that is already in hand publishes immediately.
///
/// ## The log also brings new files
///
/// On a bare `woodcase serve` — no files named, the dashboard case — the log is the only
/// thing that knows a file exists. A file first named after startup is therefore adopted
/// here: indexed, watched, warmed and announced. Without that, a `.pen` file an agent
/// created mid-session never appeared on the dashboard and was never watched, though the
/// log named it on the line that created it.
public actor ChangeCoordinator {
    /// Creates a coordinator.
    ///
    /// - Parameters:
    ///   - context: The files, caches and event hub to work against.
    ///   - matchWindow: How long a change waits for the activity log to explain it.
    ///   - pollInterval: How often the log is read while following it.
    public init(
        context: ViewerContext,
        matchWindow: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(100)
    ) {
        self.context = context
        self.matchWindow = matchWindow
        self.pollInterval = pollInterval
        matcher = ChangeMatcher(window: matchWindow)
    }

    /// The files, caches and event hub.
    public let context: ViewerContext

    /// How long a change waits for the activity log to explain it.
    public let matchWindow: Duration

    /// How often the log is read while following it.
    public let pollInterval: Duration

    /// Pairs log events with file changes; the coordinator only schedules and publishes.
    private var matcher: ChangeMatcher

    /// Matches the matcher has completed that no waiting ``fileChanged(_:)`` has claimed
    /// yet, by canonical path.
    private var completed: [String: ChangeMatcher.Match] = [:]

    /// The running presence tally.
    private var presence = PresenceTracker()

    /// The viewer's id for each served file, by canonical path, so presence — which names
    /// files by path — can be shown by id. A file the viewer does not serve has no entry
    /// and is left out of the payload.
    private var fileIDs: [String: String] = [:]

    /// The task consuming the watcher.
    private var watchTask: Task<Void, Never>?

    /// The watcher being consumed, so a file adopted mid-session can join its watch set.
    private var watcher: FileWatcher?

    /// The warming tasks for adopted files, so ``stop()`` does not leave one rendering.
    private var adoptionTasks: [Task<Void, Never>] = []

    /// One task per activity log being followed.
    private var logTasks: [Task<Void, Never>] = []

    /// Starts consuming a watcher's changes and following the activity log.
    ///
    /// - Parameter watcher: The watcher whose stream to consume. Its stream finishing —
    ///   which is what `FileWatcher.stop()` does — ends the consuming task.
    public func start(watcher: FileWatcher) {
        self.watcher = watcher
        let changes = watcher.changes
        watchTask = Task { [weak self] in
            for await url in changes {
                await self?.fileChanged(url)
            }
        }

        // Start at the end of each log: history is what `/files/{id}/activity.json` is
        // for. A stream that replayed every past edit as a live change would re-render
        // everything at startup and tell the page a dozen lies about what just happened.
        let interval = pollInterval
        logTasks = context.readers.map { reader in
            // A cursor, not a byte offset: a bundle's history is one file per writer.
            let end = (try? reader.read().cursor) ?? .start
            return Task { [weak self] in
                for await event in reader.follow(after: end, pollInterval: interval) {
                    await self?.logged(event)
                }
            }
        }
    }

    /// Stops every task. The watcher and the hub are stopped by their owner.
    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        for task in logTasks {
            task.cancel()
        }
        logTasks = []
        for task in adoptionTasks {
            task.cancel()
        }
        adoptionTasks = []
        watcher = nil
    }

    /// The presence snapshot as it stands.
    public var currentPresence: ViewerPresence {
        ViewerPresence(presence.snapshot(), fileID: { fileIDs[$0] })
    }

    /// Handles one log event: it explains a change, it is presence, and — when it names
    /// a file nobody has served yet — it is a new file to serve.
    ///
    /// - Parameter event: The event just read from the log.
    public func logged(_ event: ActivityEvent) async {
        let url = URL(fileURLWithPath: event.file)
        // Queued before adoption, so the change the adoption publishes finds the event
        // that explains it rather than waiting out the match window unattributed.
        if let match = matcher.logged(event) { completed[match.path] = match }

        let known = await context.files.file(at: url)
        let adopted = known == nil ? await context.files.adopt(url) : nil
        let file = known ?? adopted
        if let file { fileIDs[event.file] = file.id }
        presence.record(event)
        try? await context.events.broadcast(.presence, payload: currentPresence)

        if let adopted {
            welcome(adopted)
        }
    }

    /// Brings a newly indexed file up to the state every other served file is in:
    /// watched, warm, and announced to the open pages.
    ///
    /// The announcement is an ordinary `change`, because that is what a page already
    /// knows how to act on — the dashboard re-reads its file grid, and an empty
    /// dashboard reloads into a real one.
    ///
    /// - Parameter file: The file just adopted from the log.
    private func welcome(_ file: ViewerFile) {
        let watcher = watcher
        adoptionTasks.append(Task { [weak self] in
            await watcher?.watch([file.url])
            await self?.fileChanged(file.url)
            await self?.context.renders.warmThumbnails(file)
        })
    }

    /// Handles one file change: re-render, attribute, publish.
    ///
    /// - Parameter url: The file that changed, from the watcher.
    public func fileChanged(_ url: URL) async {
        guard let file = await context.files.file(at: url) else { return }

        await context.renders.invalidate(file)
        let prepared = try? await context.renders.prepared(file)
        await context.renders.warm(file)

        let events = await attribution(for: file)
        let change = ViewerChange.of(
            file: file,
            revision: prepared?.revision ?? "",
            artboards: prepared?.artboards.map(\.id) ?? [],
            changedArtboards: prepared?.artboardIDs(containing: events.flatMap(\.nodes)) ?? [],
            events: events
        )
        try? await context.events.broadcast(.change, payload: change)
    }

    // MARK: - Private

    /// The log events that explain a write, waiting up to ``matchWindow`` for them.
    ///
    /// Returns as soon as anything has arrived; an unattributed write costs the whole
    /// window once, and then only when nothing is logging.
    ///
    /// Two changes to one file can be in flight at once — the watcher's and an adopted
    /// file's announcement. They share the matcher's one waiting change, so the first to
    /// look takes its match and the other publishes unattributed rather than waiting for
    /// a match that will never come.
    private func attribution(for file: ViewerFile) async -> [ActivityEvent] {
        if let match = matcher.fileChanged(path: file.path, at: Date()) { return match.events }

        while true {
            // Awaiting inside the actor lets `logged(_:)` run and complete the match.
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                matcher.abandon(path: file.path)
                completed.removeValue(forKey: file.path)
                return []
            }
            for expired in matcher.expire(now: Date()) {
                completed[expired.path] = expired
            }
            if let match = completed.removeValue(forKey: file.path) { return match.events }
            if !matcher.isWaiting(file.path) { return [] }
        }
    }
}
