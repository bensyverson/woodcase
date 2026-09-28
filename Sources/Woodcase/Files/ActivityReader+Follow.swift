//
//  ActivityReader+Follow.swift
//  Woodcase
//

import Foundation

public extension ActivityReader {
    /// Follows the log, yielding matching events as they are appended.
    ///
    /// The first poll happens immediately, so events already in the log arrive without
    /// waiting. Ending the iteration — a `break`, or cancelling the surrounding task —
    /// stops the polling. Read errors while following are transient by nature (a log
    /// mid-rotation) and are skipped rather than ending the feed.
    ///
    /// ```swift
    /// for await event in ActivityReader(log: log).follow(from: page.nextOffset) {
    ///     show(event)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - offset: Where to start, from a previous ``Page/nextOffset``.
    ///   - file: Show only events for this .pen file.
    ///   - identity: Show only events written by this `--as` name.
    ///   - pollInterval: How long to wait between reads.
    /// - Returns: A feed of events, in log order.
    func follow(
        from offset: UInt64 = 0,
        file: URL? = nil,
        identity: String? = nil,
        pollInterval: Duration = .milliseconds(250)
    ) -> Follow {
        Follow(
            reader: self,
            offset: offset,
            file: file,
            identity: identity,
            pollInterval: pollInterval
        )
    }

    /// A live feed of an ``ActivityLog``, polled by whoever is reading it.
    ///
    /// ## Why this is a value and not a running task
    ///
    /// A feed backed by its own unstructured task — an `AsyncStream` whose producer is
    /// a `Task` started when the stream is made — begins polling the moment it exists
    /// and stops only when something reaches back to cancel it. Three ordinary
    /// situations then leave a poll loop running for the life of the process: a feed
    /// made and never iterated, a consumer torn down by fire-and-forget cleanup that
    /// has not run yet, and — the expensive one — a consumer suspended forever inside
    /// its own loop body, which keeps the producer reading and buffering behind a
    /// reader that will never take another event.
    ///
    /// That last shape is what a wedged `swift test` run looked like from outside: a
    /// host at 0 % CPU whose only live frames were two of these poll loops. Suspended
    /// tasks have no stack frames, so the wedged consumer was invisible and its
    /// producers were all the sample could show.
    ///
    /// A `Follow` has nothing to leak. It holds no task and starts no work; the polling
    /// *is* the consuming task, which means it exists exactly as long as somebody is
    /// asking for events, it stops the moment that task is cancelled, and it can never
    /// run ahead of a consumer that has stopped consuming. Iterating one twice is two
    /// independent walks from the same offset, not the leftovers of the first.
    ///
    /// The feed never ends of its own accord: a log that is quiet is a log that has
    /// nothing to say yet, not a feed that is finished. Cancellation is the ending, so
    /// a caller that needs a bounded wait must impose one.
    struct Follow: AsyncSequence, Friendly {
        /// One appended event.
        public typealias Element = ActivityEvent

        /// Creates a feed. Use ``ActivityReader/follow(from:file:identity:pollInterval:)``.
        ///
        /// - Parameters:
        ///   - reader: The reader whose log to follow.
        ///   - offset: The byte offset to start from.
        ///   - file: Show only events for this .pen file.
        ///   - identity: Show only events written by this `--as` name.
        ///   - pollInterval: How long to wait between reads.
        init(reader: ActivityReader, offset: UInt64, file: URL?, identity: String?, pollInterval: Duration) {
            self.reader = reader
            self.offset = offset
            self.file = file
            self.identity = identity
            self.pollInterval = pollInterval
        }

        /// The reader whose log this feed follows.
        public let reader: ActivityReader

        /// The byte offset every iteration starts from.
        public let offset: UInt64

        /// The .pen file this feed is narrowed to, or `nil` for all of them.
        public let file: URL?

        /// The writer this feed is narrowed to, or `nil` for all of them.
        public let identity: String?

        /// How long the consumer waits between reads.
        public let pollInterval: Duration

        /// Starts a walk of the log from ``offset``.
        ///
        /// - Returns: A fresh iterator. Two of them are independent: each keeps its own
        ///   cursor and each begins where this feed says.
        public func makeAsyncIterator() -> Iterator {
            Iterator(
                reader: reader,
                cursor: offset,
                file: file,
                identity: identity,
                pollInterval: pollInterval
            )
        }

        /// A consumer's own cursor into the log.
        ///
        /// ``next()`` drains what the last read returned before reading again, so the
        /// log file — not a buffer in memory — is what holds events a slow consumer has
        /// not reached yet.
        public struct Iterator: AsyncIteratorProtocol {
            /// Creates an iterator positioned at `cursor`.
            ///
            /// - Parameters:
            ///   - reader: The reader whose log to poll.
            ///   - cursor: The byte offset to read from next.
            ///   - file: Show only events for this .pen file.
            ///   - identity: Show only events written by this `--as` name.
            ///   - pollInterval: How long to wait between reads.
            init(reader: ActivityReader, cursor: UInt64, file: URL?, identity: String?, pollInterval: Duration) {
                self.reader = reader
                self.cursor = cursor
                self.file = file
                self.identity = identity
                self.pollInterval = pollInterval
            }

            /// The next matching event, waiting for one if the log is quiet.
            ///
            /// Cancellation is the only ending: a cancelled task gets `nil` on its next
            /// call, and gets it promptly, because the wait between reads is a
            /// cancellable sleep rather than a deadline the loop has to reach.
            ///
            /// - Returns: The next event, or `nil` once the consuming task is cancelled.
            public mutating func next() async -> ActivityEvent? {
                while true {
                    if let event = pending.popFirst() { return event }
                    if Task.isCancelled { return nil }

                    if let page = try? reader.read(from: cursor, file: file, identity: identity) {
                        cursor = page.nextOffset
                        pending = page.events[...]
                        if !pending.isEmpty { continue }
                    }

                    do {
                        try await Task.sleep(for: pollInterval)
                    } catch {
                        return nil
                    }
                }
            }

            /// The reader whose log is polled.
            private let reader: ActivityReader

            /// The .pen file this iterator is narrowed to.
            private let file: URL?

            /// The writer this iterator is narrowed to.
            private let identity: String?

            /// How long to wait between reads.
            private let pollInterval: Duration

            /// The byte offset the next read starts at.
            private var cursor: UInt64

            /// Events the last read returned that the consumer has not taken yet.
            private var pending: ArraySlice<ActivityEvent> = []
        }
    }
}
