//
//  ActivityCursor.swift
//  Woodcase
//

import Foundation

/// A position in the activity log that survives the log being rotated.
///
/// A bare byte offset only means something in the file it was taken from; once
/// ``ActivityLog`` renames that file aside, the offset points into a different, shorter
/// file and the reader can only guess. A cursor adds the file's **inode**. Rename keeps
/// the inode, so a cursor into a rotated file still names it: the reader finds the
/// archive that now has that inode, reads it from the offset, then continues through
/// every later archive and the live log from the start. See
/// ``ActivityReader/read(after:file:identity:)``.
///
/// ## A bundle's history: one position per writer
///
/// A bundle's history is one file per writer (``ActivityLog/Layout/perWriter``), so a
/// position in it is one cursor per writer file, in ``writers``, keyed by the
/// ``HistoryWriter/rawValue`` the file is named for. A writer missing from the map is
/// read from its first row — which is how a writer whose file arrives later, through a
/// sync or a `git pull`, is never skipped, even when its rows are older than the rows
/// already read. Such a cursor's own ``inode`` and ``offset`` are zero.
///
/// The string form, ``token``, is `<inode-hex>-<offset>` for one file and
/// `<writer>=<inode-hex>-<offset>,…` (writers sorted) for a bundle's history — opaque to
/// a caller, who only stores it and hands it back. ``start`` is `0-0` for both.
public struct ActivityCursor: Friendly {
    /// Creates a cursor into one file.
    ///
    /// - Parameters:
    ///   - inode: The inode of the log file the offset is into.
    ///   - offset: The byte offset just past the last line already seen.
    public init(inode: UInt64, offset: UInt64) {
        self.inode = inode
        self.offset = offset
        writers = [:]
    }

    /// Creates a cursor into a bundle's history: one position per writer's file.
    ///
    /// - Parameter writers: Each writer's position, keyed by ``HistoryWriter/rawValue``.
    ///   An empty map is ``start``.
    public init(writers: [String: ActivityCursor]) {
        inode = 0
        offset = 0
        self.writers = writers
    }

    /// Reads a cursor back from its ``token``.
    ///
    /// - Parameter token: A string produced by ``token``.
    /// - Returns: The cursor, or `nil` if the string is not one.
    public init?(token: String) {
        guard token.contains(Self.writerSeparator) else {
            guard let single = Self.single(token) else { return nil }
            self = single
            return
        }
        var writers: [String: ActivityCursor] = [:]
        for entry in token.split(separator: Self.entrySeparator) {
            let parts = entry.split(separator: Self.writerSeparator, maxSplits: 1)
            guard parts.count == 2, HistoryWriter(fileStem: String(parts[0])) != nil,
                  let position = Self.single(String(parts[1]))
            else { return nil }
            writers[String(parts[0])] = position
        }
        self.init(writers: writers)
    }

    /// The position before everything: every archive, then the live log, from byte zero
    /// — and, in a bundle's history, every writer's file from its first row.
    ///
    /// What a reader holds when the log did not exist yet — nothing was missed because
    /// nothing had been written.
    public static let start = ActivityCursor(inode: 0, offset: 0)

    /// The inode of the file ``offset`` is into; `0` means "the beginning of everything".
    public var inode: UInt64

    /// The byte offset just past the last line already seen.
    public var offset: UInt64

    /// Each writer's position in a bundle's history, keyed by ``HistoryWriter/rawValue``;
    /// empty for a cursor into one file.
    public var writers: [String: ActivityCursor]

    /// The cursor as a string: `<inode-hex>-<offset>`, or
    /// `<writer>=<inode-hex>-<offset>,…` with the writers sorted.
    public var token: String {
        guard !writers.isEmpty else { return "\(String(inode, radix: 16))-\(offset)" }
        return writers.keys.sorted()
            .map { "\($0)\(Self.writerSeparator)\(writers[$0, default: .start].token)" }
            .joined(separator: String(Self.entrySeparator))
    }

    // MARK: - Private

    /// What separates a writer from its position in a token.
    private static let writerSeparator: Character = "="

    /// What separates two writers' entries in a token.
    private static let entrySeparator: Character = ","

    /// A one-file cursor from `<inode-hex>-<offset>`.
    private static func single(_ token: String) -> ActivityCursor? {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let inode = UInt64(parts[0], radix: 16),
              let offset = UInt64(parts[1])
        else { return nil }
        return ActivityCursor(inode: inode, offset: offset)
    }
}
