//
//  ChangeMatcher.swift
//  Woodcase
//

import Foundation

/// Pairs a file change with the activity-log rows that explain it.
///
/// The two signals arrive independently: the **file** changes at the rename, and the
/// **log** row is appended a beat later. So either can come first. A log row that is
/// already in hand explains the next change at once; a change that finds nothing waits
/// for a late row, and is released unexplained once ``window`` has passed — a write
/// from an editor that does not log is a real state, not a missing one.
///
/// A pure value with time passed in, so the three cases (in hand, late-arriving, expired)
/// are testable without a clock. Whoever owns the matcher owns the ordering of calls; it
/// holds no lock and starts no task.
///
/// ```swift
/// var matcher = ChangeMatcher()
/// if let match = matcher.logged(event) { publish(match) }
/// if let match = matcher.fileChanged(path: path, at: now) { publish(match) }
/// for match in matcher.expire(now: now) { publish(match) }
/// ```
public struct ChangeMatcher: Friendly {
    /// Creates a matcher.
    ///
    /// - Parameter window: How long a change waits for the log to explain it.
    public init(window: Duration = .seconds(2)) {
        self.window = window
    }

    /// One file change and the rows that explain it.
    public struct Match: Friendly {
        /// The canonical path of the file that changed.
        public var path: String
        /// The log rows that explain the change, in log order; empty if none arrived in time.
        public var events: [ActivityEvent]
        /// When the file change was seen.
        public var changedAt: Date

        /// Whether any log row explained the change.
        public var isAttributed: Bool {
            !events.isEmpty
        }
    }

    /// How long a change waits for the log to explain it.
    public let window: Duration

    /// The paths whose change is waiting for a log row.
    public var waitingPaths: [String] {
        waiting.keys.sorted()
    }

    /// Whether a change on a path is waiting for a log row.
    ///
    /// - Parameter path: The canonical path.
    /// - Returns: `true` from ``fileChanged(path:at:)`` finding nothing until a row
    ///   completes it, it expires, or it is abandoned.
    public func isWaiting(_ path: String) -> Bool {
        waiting[path] != nil
    }

    /// Takes in one log row.
    ///
    /// - Parameter event: The row, as read from the log.
    /// - Returns: The match this row completed if its file's change was waiting;
    ///   otherwise `nil`, and the row is kept for the file's next change.
    @discardableResult
    public mutating func logged(_ event: ActivityEvent) -> Match? {
        file(event, under: event.file, arrivedAt: nil)
    }

    /// Takes in one log row on behalf of a known file, noting when it arrived.
    ///
    /// For a caller following a single file: the row is filed under `path` whatever path
    /// it names itself — a renamed bundle's older rows name its old path — and, because
    /// it has an arrival time, ``expireEvents(now:)`` releases it if no change claims it
    /// within the window, rather than letting it explain some later, unrelated change.
    ///
    /// - Parameters:
    ///   - event: The row, as read from the log. Delivered unchanged in any match.
    ///   - path: The canonical path the row explains.
    ///   - now: When the row was read.
    /// - Returns: The match this row completed if the file's change was waiting;
    ///   otherwise `nil`, and the row is kept for the file's next change.
    @discardableResult
    public mutating func logged(_ event: ActivityEvent, path: String, at now: Date) -> Match? {
        file(event, under: path, arrivedAt: now)
    }

    /// Releases every row that has waited out the window with no change to claim it.
    ///
    /// Only rows taken in with an arrival time (``logged(_:path:at:)``) ever expire.
    ///
    /// - Parameter now: The current time.
    /// - Returns: The released rows, in the order they were logged.
    public mutating func expireEvents(now: Date) -> [ActivityEvent] {
        let seconds = windowSeconds
        var released: [ActivityEvent] = []
        for path in pending.keys.sorted() {
            guard let rows = pending[path] else { continue }
            let isDue = { (row: Pending) in
                row.arrivedAt.map { now.timeIntervalSince($0) >= seconds } ?? false
            }
            released += rows.filter(isDue).map(\.event)
            let kept = rows.filter { !isDue($0) }
            pending[path] = kept.isEmpty ? nil : kept
        }
        return released
    }

    /// Takes in one file change.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the file that changed.
    ///   - now: The current time.
    /// - Returns: The match if rows for the file are already in hand; otherwise `nil`, and
    ///   the change waits for ``logged(_:)`` or ``expire(now:)``. A change on a path that
    ///   is already waiting keeps the earlier clock.
    public mutating func fileChanged(path: String, at now: Date) -> Match? {
        let events = take(path)
        guard !events.isEmpty else {
            waiting[path] = waiting[path] ?? now
            return nil
        }
        waiting.removeValue(forKey: path)
        return Match(path: path, events: events, changedAt: now)
    }

    /// Releases every change that has waited out the window.
    ///
    /// - Parameter now: The current time.
    /// - Returns: One unattributed match per expired change, oldest first.
    public mutating func expire(now: Date) -> [Match] {
        let seconds = windowSeconds
        let due = waiting
            .filter { now.timeIntervalSince($0.value) >= seconds }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        for (path, _) in due {
            waiting.removeValue(forKey: path)
        }
        return due.map { Match(path: $0.key, events: [], changedAt: $0.value) }
    }

    /// Forgets a waiting change, for a caller that stopped waiting on it.
    ///
    /// Without this a canceled wait leaves its clock behind, and the path's next change
    /// would inherit it and expire early.
    ///
    /// - Parameter path: The canonical path whose change is no longer awaited.
    public mutating func abandon(path: String) {
        waiting.removeValue(forKey: path)
    }

    // MARK: - Private

    /// A row read but not yet attached to a change.
    private struct Pending: Friendly {
        /// The row.
        var event: ActivityEvent
        /// When it was read, or `nil` for a row that never expires.
        var arrivedAt: Date?
    }

    /// Rows read but not yet attached to a change, by canonical path.
    private var pending: [String: [Pending]] = [:]

    /// When each waiting change was seen.
    private var waiting: [String: Date] = [:]

    /// ``window`` in seconds, to compare against `Date` intervals.
    private var windowSeconds: TimeInterval {
        Double(window.components.seconds) + Double(window.components.attoseconds) / 1e18
    }

    private mutating func file(_ event: ActivityEvent, under path: String, arrivedAt: Date?) -> Match? {
        pending[path, default: []].append(Pending(event: event, arrivedAt: arrivedAt))
        guard let changedAt = waiting.removeValue(forKey: path) else { return nil }
        return Match(path: path, events: take(path), changedAt: changedAt)
    }

    private mutating func take(_ path: String) -> [ActivityEvent] {
        pending.removeValue(forKey: path)?.map(\.event) ?? []
    }
}
