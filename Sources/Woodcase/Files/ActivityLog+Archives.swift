//
//  ActivityLog+Archives.swift
//  Woodcase
//

extension ActivityLog {
    /// A rotated log file and the inode it kept through the rename.
    typealias Archive = JSONLinesFile.Archive

    /// The rotated logs beside the live one, oldest first.
    ///
    /// - Returns: Every `activity.<stamp>.jsonl`; empty when the directory is missing or
    ///   holds none. A ``ViewLog``'s archives beside them are not included.
    func archives() -> [Archive] {
        lines.archives()
    }
}
