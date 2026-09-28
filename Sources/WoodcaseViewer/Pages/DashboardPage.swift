//
//  DashboardPage.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /` — every file the viewer is serving, and what has just happened to them.
///
/// A composition and nothing else: a ``TopBar``, a ``FileList``, an ``ActivityFeed``.
/// The page holds no markup of its own, which is what makes each of those three
/// previewable and testable on its own.
public struct DashboardPage: HTML {
    /// Creates a dashboard.
    ///
    /// - Parameters:
    ///   - files: The files, as `GET /files` reports them.
    ///   - events: Recent activity across every file, oldest first.
    ///   - presence: Who has been writing, in the log's order of first appearance.
    ///   - clock: The moment the page is rendered for.
    ///   - logPath: Where the activity log lives.
    public init(
        files: [FileListReport.Summary],
        events: [ActivityEvent],
        presence: [ViewerPresence.Identity],
        clock: ViewerClock,
        logPath: String
    ) {
        self.files = files
        self.events = events
        self.presence = presence
        self.clock = clock
        self.logPath = logPath
    }

    /// The files, as `GET /files` reports them.
    public let files: [FileListReport.Summary]

    /// Recent activity across every file, oldest first.
    public let events: [ActivityEvent]

    /// Who has been writing.
    public let presence: [ViewerPresence.Identity]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// Where the activity log lives.
    public let logPath: String

    public var body: some HTML {
        ViewerDocument(title: "Files · woodcase serve", layout: .dashboard) {
            TopBar(
                crumbs: [],
                presence: presence,
                clock: clock,
                subject: .files
            )
            main(.class("v-main")) {
                FileList(
                    files: files,
                    clock: clock,
                    logPath: logPath,
                    eventCount: events.count
                )
                ActivityFeed(
                    events: events,
                    clock: clock,
                    scope: "all files · all identities",
                    showsFile: true,
                    limit: 20
                )
            }
        }
    }
}
