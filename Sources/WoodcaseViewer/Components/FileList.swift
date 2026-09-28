//
//  FileList.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The dashboard's grid: every .pen file the viewer is serving, as a ``FileCard`` with a
/// rendered thumbnail, most recently changed first.
///
/// The order is the answer to the question a person opening this page is actually
/// asking — *what just changed?* — so it is by last change, not alphabetical, and a file
/// nobody has touched sorts last rather than being hidden.
///
/// A grid rather than a list of rows, because a card can carry a real render of the file
/// and a 30-pixel row cannot; it also fits several times as many recent files on one
/// screen. The columns are `auto-fill`, so the count follows the window and the component
/// declares no breakpoints of its own.
public struct FileList: HTML {
    /// Creates a list.
    ///
    /// - Parameters:
    ///   - files: The files, as `GET /files` reports them.
    ///   - clock: The moment the page is rendered for.
    ///   - logPath: Where the activity log lives, for the header line.
    ///   - eventCount: How many events that log holds.
    public init(
        files: [FileListReport.Summary],
        clock: ViewerClock,
        logPath: String,
        eventCount: Int
    ) {
        self.files = files
        self.clock = clock
        self.logPath = logPath
        self.eventCount = eventCount
    }

    /// The files, as `GET /files` reports them.
    public let files: [FileListReport.Summary]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// Where the activity log lives.
    public let logPath: String

    /// How many events that log holds.
    public let eventCount: Int

    /// The files, most recently changed first, with never-changed files last.
    var ordered: [FileListReport.Summary] {
        files.sorted { left, right in
            switch (left.lastChange?.time, right.lastChange?.time) {
            case let (.some(a), .some(b)): a > b
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): left.name < right.name
            }
        }
    }

    public var body: some HTML {
        section(.class("v-files"), .id("v-files")) {
            header(.class("v-section-head")) {
                div(.class("v-section-titles")) {
                    h1(.class("v-section-title")) { "Files" }
                    p(.class("v-section-subtitle")) {
                        "Every .pen the activity log has seen, most recent change first."
                    }
                }
                span(.class("v-mono v-section-note")) {
                    "\(logPath) · \(eventCount) \(eventCount == 1 ? "event" : "events")"
                }
            }
            div(.class("v-file-cards")) {
                for summary in ordered {
                    FileCard(summary: summary, clock: clock)
                }
            }
        }
    }
}
