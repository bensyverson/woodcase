//
//  ActivityRowFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders activity events as the one-line-per-event outline `woodcase activity` prints.
///
/// Four columns, separated by `" | "`: the local time, the writer's identity, the verb
/// — padded to the width of the longest one, so the column after it lines up across
/// rows — and the first path the event touched, with `+N` when it touched more than
/// one. An event that touches no node at all — a variable, an import, a theme axis —
/// shows `-` in the path column, because there is nothing to name.
///
/// ```text
/// 16:31:04 | ana | set      | layout-vertical/first
/// 16:31:05 | ana | theme    | -
/// ```
///
/// This is the human-readable form only. `--json` bypasses it entirely and prints each
/// ``ActivityEvent``'s own wire form instead — see `Activity`.
enum ActivityRowFormatter {
    /// The width every verb column is padded to: the longest ``ActivityEvent/Kind``
    /// raw value.
    static let verbColumnWidth = ActivityEvent.Kind.allCases.map(\.rawValue.count).max() ?? 0

    /// Renders one event as a row.
    ///
    /// - Parameters:
    ///   - event: The event to render.
    ///   - timeZone: The time zone the time column is shown in. Defaults to the
    ///     system's.
    /// - Returns: The row, with no trailing newline.
    static func row(for event: ActivityEvent, timeZone: TimeZone = .current) -> String {
        let time = timeFormat(for: timeZone).format(event.time)
        let verb = event.op.rawValue.padding(
            toLength: verbColumnWidth, withPad: " ", startingAt: 0
        )
        return "\(time) | \(event.identity) | \(verb) | \(pathSummary(for: event))"
    }

    /// Renders events as rows, one per line, in the order given.
    ///
    /// - Parameters:
    ///   - events: The events to render. The caller orders them — oldest first, to
    ///     read as a feed with the newest event last.
    ///   - timeZone: The time zone the time column is shown in. Defaults to the
    ///     system's.
    /// - Returns: The rows joined by newlines, with no trailing newline. Empty for an
    ///   empty list.
    static func text(_ events: [ActivityEvent], timeZone: TimeZone = .current) -> String {
        events.map { row(for: $0, timeZone: timeZone) }.joined(separator: "\n")
    }

    // MARK: - Private

    /// The time column's format: 24-hour `HH:mm:ss`, no date, in the given time zone.
    private static func timeFormat(for timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
    }

    /// The path column: the first path touched, plus `+N` for `N` more, or `-` when
    /// the event touched no node.
    private static func pathSummary(for event: ActivityEvent) -> String {
        guard let first = event.paths.first else { return "-" }
        guard event.paths.count > 1 else { return first }
        return "\(first) +\(event.paths.count - 1)"
    }
}
