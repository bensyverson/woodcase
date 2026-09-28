//
//  ViewerContext.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Everything a route handler can reach: the files being served, the warm render cache,
/// the activity logs, and the event hub.
///
/// It is passed to every handler on its ``ViewerRequest``, which is what lets a page
/// component be written without knowing anything about the server that called it — and
/// what lets a handler be tested by building a context and calling it directly, with no
/// socket in sight.
///
/// ## Why *logs*, plural
///
/// A log belongs to a project, so `woodcase serve` over files from two projects follows
/// two of them. Reads here merge every log in time order and are the only way handlers
/// see the feed, so a page cannot accidentally show one project's history and call it
/// everything.
public struct ViewerContext: Sendable {
    /// Creates a context over several activity logs.
    ///
    /// - Parameters:
    ///   - files: The files being served.
    ///   - renders: The warm render cache.
    ///   - logs: The activity logs to read history, identity and presence from, in the
    ///     order they should be listed. Duplicates are collapsed.
    ///   - events: The open `/events` streams.
    public init(
        files: ViewerFileIndex,
        renders: RenderCache,
        logs: [ActivityLog],
        events: SSEHub
    ) {
        self.files = files
        self.renders = renders
        self.logs = ViewerContext.distinct(logs)
        self.events = events
    }

    /// Creates a context over one activity log.
    ///
    /// - Parameters:
    ///   - files: The files being served.
    ///   - renders: The warm render cache.
    ///   - log: The activity log to read history, identity and presence from.
    ///   - events: The open `/events` streams.
    public init(
        files: ViewerFileIndex,
        renders: RenderCache,
        log: ActivityLog,
        events: SSEHub
    ) {
        self.init(files: files, renders: renders, logs: [log], events: events)
    }

    /// The files being served, and the id → file lookup.
    public let files: ViewerFileIndex

    /// The warm render cache: prepared documents and rendered PNGs.
    public let renders: RenderCache

    /// The activity logs the viewer reads history, identity and presence from.
    public let logs: [ActivityLog]

    /// The open `/events` streams.
    public let events: SSEHub

    /// A reader per log, in the same order.
    public var readers: [ActivityReader] {
        logs.map(ActivityReader.init(log:))
    }

    /// The most recent events across every log, oldest last-written first.
    ///
    /// Each log is read independently and the results merged by time, because a file's
    /// events live in exactly one log and no log knows about the others. A log that
    /// cannot be read contributes nothing rather than failing the read: an unreachable
    /// project should not empty the feed of the reachable ones.
    ///
    /// - Parameters:
    ///   - count: How many of the most recent events to return.
    ///   - file: Show only events for this .pen file, or `nil` for every file.
    /// - Returns: The events, oldest first.
    public func tail(count: Int, file: URL? = nil) -> [ActivityEvent] {
        Array(merged(readers.compactMap { try? $0.tail(count: count, file: file) }).suffix(count))
    }

    /// Every event in every log, oldest first — what presence is folded out of.
    ///
    /// - Returns: The events, oldest first.
    public func allEvents() -> [ActivityEvent] {
        merged(readers.compactMap { try? $0.read().events })
    }

    // MARK: - Private

    /// Logs deduplicated by the file they point at, first appearance first.
    private static func distinct(_ logs: [ActivityLog]) -> [ActivityLog] {
        var seen: Set<String> = []
        return logs.filter { seen.insert($0.fileURL.standardizedFileURL.path).inserted }
    }

    /// Several logs' events as one feed, oldest first.
    private func merged(_ pages: [[ActivityEvent]]) -> [ActivityEvent] {
        guard pages.count > 1 else { return pages.first ?? [] }
        return pages.flatMap(\.self).sorted { $0.time < $1.time }
    }
}
