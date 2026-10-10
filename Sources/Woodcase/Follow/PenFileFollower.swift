//
//  PenFileFollower.swift
//  Woodcase
//

import Foundation

/// Follows one document: each change to its file, with the activity-log rows that
/// explain it, and each attributed read of it, as an `AsyncSequence`.
///
/// It composes the pieces a viewer or an editor would otherwise wire by hand: a
/// ``FileWatcher`` on the document, an ``ActivityReader`` on its log, a ``ViewReader``
/// on the ``ViewLog`` beside it, and a ``ChangeMatcher`` pairing changes with rows. A
/// change written through woodcase arrives as one ``Event/changed(_:)`` carrying its
/// rows — who wrote it, which nodes, at what revision; a change no tool logged arrives
/// unattributed once ``matchWindow`` has passed; a row whose change the follower never
/// saw arrives as ``Event/activity(_:)``; and a read by an identity (`woodcase get --as
/// claude`) arrives as ``Event/viewed(_:)``. Changes and views are each in log order;
/// between the two, order is by poll.
///
/// ```swift
/// let follower = PenFileFollower(file: url)   // a .pen, or a .umbra bundle
/// var presence = PresenceTracker()
/// for await event in follower {
///     presence.record(event)
///     if case let .changed(change) = event, change.isAttributed { highlight(change.nodes) }
/// }
/// ```
///
/// ## A value, like ``ActivityReader/Follow``
///
/// The follower holds no task and starts no work. Iterating it *is* the polling: each
/// call to ``Iterator/next()`` drains the watcher, reads the log from its cursor and runs
/// the matcher, then sleeps ``pollInterval`` when there is nothing to say. Canceling the
/// consuming task ends the iteration, stops the watcher and releases it; so does
/// breaking out of the loop. Iterating twice is two independent walks from the same
/// ``start``.
///
/// ## What it touches
///
/// The watcher watches the document's own folder — the bundle for a `.umbra`, the
/// file's folder for a bare `.pen` — and the logs are read, never written or watched, so
/// following needs no write access anywhere. The logs are ``ActivityLogLocation``'s
/// answer unless one is passed: inside the bundle for a `.umbra`, at the repository
/// root (or `$WOODCASE_HOME`) for a bare `.pen` — which a sandboxed reader of a bare
/// file can reach only with access to that directory.
public struct PenFileFollower: AsyncSequence, Friendly {
    /// One thing that happened to the followed document.
    public typealias Element = Event

    /// Creates a follower.
    ///
    /// - Parameters:
    ///   - file: The document: a bare `.pen`, a `.umbra` bundle, or the `document.pen`
    ///     inside one.
    ///   - log: The activity log to read. Defaults to ``ActivityLogLocation/log(for:environment:)``.
    ///   - start: Where to begin. ``Start/end`` is resolved now, so a write made after
    ///     this initializer returns is never missed, however late iteration begins.
    ///   - matchWindow: How long a change waits for a row to explain it, and how long a
    ///     row waits for its change, before each is delivered alone.
    ///   - pollInterval: How long the consumer sleeps between reads when nothing happened.
    ///   - backend: How the watcher notices writes.
    public init(
        file: URL,
        log: ActivityLog? = nil,
        from start: Start = .end,
        matchWindow: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(100),
        backend: FileWatcher.Backend = .native
    ) {
        let location = PenLocation(file)
        document = location.document
        let log = log ?? ActivityLogLocation.log(for: file)
        self.log = log
        self.start = start
        self.matchWindow = matchWindow
        self.pollInterval = pollInterval
        self.backend = backend
        switch start {
        case .end:
            origin = Position(
                activity: ActivityReader(log: log).endCursor(),
                views: ViewReader(log: ViewLog(beside: log)).endCursor()
            )
            baseline = FileSignature.read(at: location.document.path)
        case .beginning:
            origin = Position(activity: .start, views: .start)
            baseline = nil
        case let .position(position):
            origin = position
            baseline = nil
        }
    }

    /// The `.pen` file being followed: `document.pen` for a bundle.
    public let document: URL

    /// The activity log being read.
    public let log: ActivityLog

    /// Where following begins, as asked.
    public let start: Start

    /// How long a change and a row each wait for the other.
    public let matchWindow: Duration

    /// How long the consumer sleeps between reads when nothing happened.
    public let pollInterval: Duration

    /// How the watcher notices writes.
    public let backend: FileWatcher.Backend

    /// Starts a walk from ``start``.
    ///
    /// - Returns: A fresh iterator. Two are independent; each makes its own watcher.
    public func makeAsyncIterator() -> Iterator {
        Iterator(follower: self)
    }

    // MARK: - Internal

    /// ``start`` resolved to log positions.
    let origin: Position

    /// The document's signature when ``Start/end`` was resolved, so a write that lands
    /// before the watcher is armed is still noticed.
    let baseline: FileSignature?

    /// The key the matcher files every change and row under: there is only one file.
    var matchKey: String {
        ActivityEvent.canonicalPath(for: document)
    }
}
