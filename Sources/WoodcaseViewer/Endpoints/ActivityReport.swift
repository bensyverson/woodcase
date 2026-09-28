//
//  ActivityReport.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The body of `GET /files/{file}/activity.json`: the recent activity-log events for
/// one file, oldest first.
///
/// The events are ``ActivityEvent`` values — the log's own struct, not a copy of it —
/// so a consumer that already reads `activity.jsonl` needs no second decoder and the
/// two shapes cannot drift.
public struct ActivityReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameters:
    ///   - file: The file's id, or `nil` when the report spans every file.
    ///   - events: The events, oldest first.
    public init(file: String?, events: [ActivityEvent]) {
        self.file = file
        self.events = events
    }

    /// The file's id, or `nil` when the report spans every file.
    public let file: String?

    /// The events, oldest first.
    public let events: [ActivityEvent]
}
