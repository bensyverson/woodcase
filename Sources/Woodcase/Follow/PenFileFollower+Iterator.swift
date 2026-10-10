//
//  PenFileFollower+Iterator.swift
//  Woodcase
//

import Foundation

public extension PenFileFollower {
    /// One consumer's walk of a followed document.
    ///
    /// It owns everything the walk needs — the watcher, the log cursor, the matcher — and
    /// nothing outlives it: canceling the consuming task stops the watcher on the next
    /// call, and dropping the iterator releases it.
    struct Iterator: AsyncIteratorProtocol {
        /// Creates an iterator. Use ``PenFileFollower/makeAsyncIterator()``.
        ///
        /// For ``Start/since(_:)`` it walks each log back from where the history ends to
        /// the date — the one read that start costs before the first ``next()``.
        ///
        /// - Parameter follower: What to follow, and how.
        init(follower: PenFileFollower) {
            self.follower = follower
            var origin = follower.origin
            if case let .since(date) = follower.start {
                history = History(date: date, end: follower.origin)
                origin = History.start(of: follower, since: date)
            }
            position = origin
            readCursor = origin.activity
            viewCursor = origin.views
            matcher = ChangeMatcher(window: follower.matchWindow)
            isReplaying = follower.start != .end
            baseline = follower.baseline
        }

        /// How far this walk has delivered: hand it to ``Start/position(_:)`` to resume
        /// just after the last event ``next()`` returned.
        ///
        /// Rows read but not yet delivered — waiting for their change — are not counted,
        /// so a resumed follower reads them again rather than losing them.
        public private(set) var position: Position

        /// The next event, waiting for one if nothing is happening.
        ///
        /// Cancellation is the only ending: a canceled task gets `nil` promptly, because
        /// the wait between reads is a cancelable sleep, and the watcher is stopped
        /// before it returns.
        ///
        /// - Returns: The next event, or `nil` once the consuming task is canceled.
        public mutating func next() async -> Event? {
            while true {
                if let next = ready.popFirst() {
                    position = next.position
                    return next.event
                }
                if isFinished || Task.isCancelled {
                    await finish()
                    return nil
                }
                if watcher == nil {
                    await arm()
                }
                await poll()
                if !ready.isEmpty { continue }
                do {
                    try await Task.sleep(for: follower.pollInterval)
                } catch {
                    await finish()
                    return nil
                }
            }
        }

        /// Called with the watcher once it is made, so a test can watch it go away.
        var watcherCreated: (@Sendable (FileWatcher) -> Void)?

        // MARK: - Private

        /// An event ready to return, and the position just after it.
        private struct Ready: Friendly {
            var event: Event
            var position: Position
        }

        /// What is left of a ``Start/since(_:)`` history: the date, and where in each log
        /// the history ends. Each half is cleared once it has been read.
        private struct History: Friendly {
            /// The window's oldest moment.
            var date: Date
            /// Where the activity history ends; `nil` once it has been read.
            var activityEnd: ActivityCursor?
            /// Where the view history ends; `nil` once it has been read.
            var viewsEnd: ActivityCursor?

            /// A history not yet read in either log.
            ///
            /// - Parameters:
            ///   - date: The window's oldest moment.
            ///   - end: Where each log's history ends.
            init(date: Date, end: Position) {
                self.date = date
                activityEnd = end.activity
                viewsEnd = end.views
            }

            /// Where the window begins in each log, walking back from `follower`'s origin.
            ///
            /// A log the walk cannot read starts at the history's end instead: its window
            /// is not delivered, and what is new still is.
            ///
            /// - Parameters:
            ///   - follower: The follower whose origin is where the history ends.
            ///   - date: The window's oldest moment.
            /// - Returns: Where each log's window begins.
            static func start(of follower: PenFileFollower, since date: Date) -> Position {
                let end = follower.origin
                let activity = ActivityReader(log: follower.log)
                let views = ViewReader(log: ViewLog(beside: follower.log))
                return Position(
                    activity: (try? activity.cursor(since: date, through: end.activity)) ?? end.activity,
                    views: (try? views.cursor(since: date, through: end.views)) ?? end.views
                )
            }
        }

        private let follower: PenFileFollower

        /// Made on the first call, so a follower that is never iterated watches nothing.
        private var watcher: FileWatcher?

        private var matcher: ChangeMatcher

        /// Where the next activity-log read starts.
        private var readCursor: ActivityCursor

        /// Where the next view-log read starts.
        private var viewCursor: ActivityCursor

        /// The cursor just before each row the matcher holds, oldest first: the place a
        /// resumed follower must read from to see them again.
        private var unclaimed = FIFOQueue<ActivityCursor>()

        /// Whether the next read is history — rows whose writes nobody watched.
        private var isReplaying: Bool

        /// The file as it was when ``Start/end`` was resolved; compared once, on arming.
        private var baseline: FileSignature?

        /// Events waiting to be returned, oldest first.
        private var ready = FIFOQueue<Ready>()

        /// The part of a ``Start/since(_:)`` history not yet read; `nil` for other starts.
        private var history: History?

        /// Whether the walk has ended; later calls return `nil` without re-arming.
        private var isFinished = false

        /// Starts the watcher, falling back to polling when the native one cannot watch.
        ///
        /// The native watcher needs an event-only descriptor on the document's folder,
        /// which a process that may reach the file but not list its folder — a sandboxed
        /// app holding a grant on one `.pen` — is refused. Polling needs only `stat` on
        /// the file, so it is the fallback rather than following nothing in silence.
        private mutating func arm() async {
            var watcher = FileWatcher(backend: follower.backend)
            await watcher.watch([follower.document])
            if await watcher.watchedCount == 0, follower.backend != .polling {
                await watcher.stop()
                watcher = FileWatcher(backend: .polling)
                await watcher.watch([follower.document])
            }
            self.watcher = watcher
            watcherCreated?(watcher)
        }

        /// Stops and releases the watcher.
        private mutating func finish() async {
            isFinished = true
            await watcher?.stop()
            watcher = nil
        }

        /// One round: read new rows, take in file changes, release what waited too long.
        private mutating func poll() async {
            let now = Date()
            let key = follower.matchKey
            readRows(now: now, key: key)
            readViews()

            let drained = await watcher?.drain() ?? []
            var changed = !drained.isEmpty
            if let baseline {
                changed = changed || FileSignature.read(at: follower.document.path) != baseline
                self.baseline = nil
            }
            if changed, let match = matcher.fileChanged(path: key, at: now) {
                deliver(match)
            }
            for match in matcher.expire(now: now) {
                deliver(match)
            }
            for event in matcher.expireEvents(now: now) {
                unclaimed.removeFirst(upTo: 1)
                emit(.activity(event))
            }
        }

        /// Reads the log from the cursor and hands each row on.
        private mutating func readRows(now: Date, key: String) {
            let reader = ActivityReader(log: follower.log)
            let read: ActivityReader.Page? = if let history, let end = history.activityEnd {
                try? reader.read(after: readCursor, through: end, since: history.date, file: follower.document)
            } else {
                try? reader.read(after: readCursor, file: follower.document)
            }
            guard let page = read else { return }
            if page.restarted {
                emit(.restarted)
            }
            var before = readCursor
            for (event, after) in zip(page.events, page.eventCursors) {
                readCursor = after
                if isReplaying {
                    emit(.activity(event))
                } else {
                    unclaimed.append(before)
                    if let match = matcher.logged(event, path: key, at: now) {
                        deliver(match)
                    }
                }
                before = after
            }
            readCursor = page.cursor ?? readCursor
            isReplaying = false
            history?.activityEnd = nil
        }

        /// Reads the view log from its cursor. A view needs no matching: it is delivered
        /// as read, history included.
        private mutating func readViews() {
            let reader = ViewReader(log: ViewLog(beside: follower.log))
            let read: ViewReader.Page? = if let history, let end = history.viewsEnd {
                try? reader.read(after: viewCursor, through: end, since: history.date, file: follower.document)
            } else {
                try? reader.read(after: viewCursor, file: follower.document)
            }
            guard let page = read else { return }
            for (view, after) in zip(page.events, page.eventCursors) {
                viewCursor = after
                emit(.viewed(view))
            }
            viewCursor = page.cursor ?? viewCursor
            history?.viewsEnd = nil
        }

        /// Queues a change, and stops counting its rows as unclaimed.
        private mutating func deliver(_ match: ChangeMatcher.Match) {
            unclaimed.removeFirst(upTo: match.events.count)
            emit(.changed(FileChange(events: match.events, changedAt: match.changedAt)))
        }

        /// Queues an event with the position a consumer resumes from after taking it.
        private mutating func emit(_ event: Event) {
            ready.append(Ready(
                event: event,
                position: Position(activity: unclaimed.first ?? readCursor, views: viewCursor)
            ))
        }
    }
}
