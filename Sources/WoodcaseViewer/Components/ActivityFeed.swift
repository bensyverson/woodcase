//
//  ActivityFeed.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The activity feed: the log, newest first, as ``ActivityRow``s.
///
/// The events are ``ActivityEvent`` values straight from `activity.jsonl` — the log's
/// own struct — so the feed cannot say something the log does not, and a tool reading
/// the file sees exactly what the page shows.
///
/// Also the fragment served at `GET /files/{file}/activity`.
public struct ActivityFeed: HTML {
    /// Creates a feed.
    ///
    /// - Parameters:
    ///   - events: The events to show, oldest first as the reader returns them.
    ///   - clock: The moment the page is rendered for.
    ///   - scope: What the feed is filtered to, for the header line.
    ///   - showsFile: Whether rows name their file, which the dashboard needs.
    ///   - limit: How many rows to draw at most.
    public init(
        events: [ActivityEvent],
        clock: ViewerClock,
        scope: String,
        showsFile: Bool = false,
        limit: Int = 50
    ) {
        self.events = events
        self.clock = clock
        self.scope = scope
        self.showsFile = showsFile
        self.limit = limit
    }

    /// The events to show, oldest first.
    public let events: [ActivityEvent]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// What the feed is filtered to.
    public let scope: String

    /// Whether rows name their file.
    public let showsFile: Bool

    /// How many rows to draw at most.
    public let limit: Int

    /// The rows actually drawn: newest first, capped.
    ///
    /// The reader hands back oldest-first because that is the order the file is written
    /// in; a feed is read from the top, so the reversal happens here, once.
    var visible: [ActivityEvent] {
        Array(events.reversed().prefix(limit))
    }

    public var body: some HTML {
        section(.class("v-panel v-activity"), .id(ViewerLink.Fragment.activity.target)) {
            header(.class("v-panel-head")) {
                h2(.class("v-panel-title")) { "Activity" }
                span(.class("v-panel-note")) { scope }
            }
            if visible.isEmpty {
                p(.class("v-empty-note")) { "Nothing has been recorded yet." }
            } else {
                div(.class("v-activity-rows")) {
                    for event in visible {
                        ActivityRow(event: event, clock: clock, showsFile: showsFile)
                    }
                }
            }
        }
    }
}
