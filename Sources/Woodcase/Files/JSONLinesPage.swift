//
//  JSONLinesPage.swift
//  Woodcase
//

/// What one read of a ``JSONLinesFile`` produced, before a typed reader wraps it in its
/// own public page.
struct JSONLinesPage<Row: JSONLinesRow> {
    /// The rows that passed the filter, in file order.
    var rows: [Row] = []

    /// The position just after each of ``rows``.
    var rowCursors: [ActivityCursor] = []

    /// The offset just past the last complete line, in the file read last.
    var nextOffset: UInt64

    /// Whether the read could not follow its starting point and began again.
    var restarted: Bool

    /// How many complete lines did not decode.
    var skippedLines: Int = 0

    /// Where to resume; `nil` when nothing was read from a file.
    var cursor: ActivityCursor?
}
