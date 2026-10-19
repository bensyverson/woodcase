//
//  ChangesFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders a ``Woodcase/ChangeFeed/Report`` as the lines `woodcase changes` prints.
///
/// Notes first — a first look, a rotated-away cursor, a file changed outside woodcase —
/// then one row per change, then the cursor, always last, so a caller can take it with
/// `tail -1`:
///
/// ```text
/// 16:31:04  ben  set    Home/Hero/Title  kind.content: "Welcome" → "Welcome back"
/// 16:31:09  ben  add    Home/Note  added note "Warmer, please" in Home at 2
/// cursor 1a2b3c-40960
/// ```
///
/// A row is time, writer, the row's verb padded to the widest verb, and the change's
/// own line (``Woodcase/ActivityChangeSummary/Change/line``), which reads back as the
/// `set` that would repeat it.
enum ChangesFormatter {
    /// The report as lines.
    ///
    /// - Parameters:
    ///   - report: The report.
    ///   - file: The file as the caller named it, for the commands a note suggests.
    ///   - writers: Whose rows were asked for, for the empty-feed sentence.
    ///   - timeZone: The time zone the time column is shown in.
    /// - Returns: The lines, without newlines.
    static func lines(
        _ report: ChangeFeed.Report,
        file: String,
        writers: ChangeFeed.Writers,
        timeZone: TimeZone = .current
    ) -> [String] {
        var lines = notes(report, file: file)
        let rows = report.changes.flatMap { summary in summary.changes.map { (summary, $0) } }
        let who = rows.map { name(of: $0.0.identity) }
        let width = who.map(\.count).max() ?? 0
        let time = timeFormat(for: timeZone)
        for ((summary, change), name) in zip(rows, who) {
            let verb = summary.op.rawValue.padding(
                toLength: ActivityRowFormatter.verbColumnWidth, withPad: " ", startingAt: 0
            )
            let writer = name.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("\(time.format(summary.time))  \(writer)  \(verb)  \(change.line)")
        }
        if rows.isEmpty, report.unlogged == nil, report.origin != .firstLook {
            lines.append(writers == .others ? "no changes by others since \(report.since.token)"
                : "no changes since \(report.since.token)")
        }
        lines.append("cursor \(report.cursor.token)")
        return lines
    }

    // MARK: - Private

    private static func notes(_ report: ChangeFeed.Report, file: String) -> [String] {
        var notes: [String] = []
        if report.origin == .firstLook {
            notes.append("""
            note  first look at \(file) as \(report.identity): the feed starts here, at the end \
            of the log. Run `woodcase changes \(file)` on your next turn to see what others \
            changed since; --since \(ActivityCursor.start.token) reads the whole history.
            """)
        }
        if report.restarted {
            notes.append("""
            note  the log rotated past your cursor and that archive is gone, so some rows are \
            missing — re-read the file: `woodcase tree \(file)`
            """)
        }
        if let unlogged = report.unlogged {
            notes.append("""
            note  \(file) changed outside woodcase since rev \(unlogged.since.prefix(8)) — the log \
            has no record of what changed; re-read it: `woodcase tree \(file)`
            """)
        }
        return notes
    }

    /// The writer column: the name, or `unattributed` for nobody.
    private static func name(of identity: String) -> String {
        identity == ActivityEvent.unattributed ? "unattributed" : identity
    }

    /// The time column's format: 24-hour `HH:mm:ss`, as `woodcase activity` prints it.
    private static func timeFormat(for timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
    }
}
