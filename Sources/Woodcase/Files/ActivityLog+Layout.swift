//
//  ActivityLog+Layout.swift
//  Woodcase
//

public extension ActivityLog {
    /// How a log is laid out on disk.
    ///
    /// It follows from the log's ``ActivityLog/Origin`` — a bundle's history is
    /// ``perWriter``, every other log ``single`` — and decides how the log is appended to
    /// and read.
    enum Layout: Friendly {
        /// One `activity.jsonl` that every writer appends to: a bare file's log, local
        /// state kept out of Git.
        case single

        /// One file per ``HistoryWriter`` in a bundle's `history/` — `ben@grace.jsonl` —
        /// each appended only by its writer and merged by time when read: a shared
        /// history, meant to be committed and synced.
        case perWriter
    }
}
