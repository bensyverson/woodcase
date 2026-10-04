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
/// The string form, ``token``, is `<inode-hex>-<offset>` — opaque to a caller, who only
/// stores it and hands it back.
public struct ActivityCursor: Friendly {
    /// Creates a cursor.
    ///
    /// - Parameters:
    ///   - inode: The inode of the log file the offset is into.
    ///   - offset: The byte offset just past the last line already seen.
    public init(inode: UInt64, offset: UInt64) {
        self.inode = inode
        self.offset = offset
    }

    /// Reads a cursor back from its ``token``.
    ///
    /// - Parameter token: A string produced by ``token``.
    /// - Returns: The cursor, or `nil` if the string is not one.
    public init?(token: String) {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let inode = UInt64(parts[0], radix: 16),
              let offset = UInt64(parts[1])
        else { return nil }
        self.init(inode: inode, offset: offset)
    }

    /// The position before everything: every archive, then the live log, from byte zero.
    ///
    /// What a reader holds when the log did not exist yet — nothing was missed because
    /// nothing had been written.
    public static let start = ActivityCursor(inode: 0, offset: 0)

    /// The inode of the file ``offset`` is into; `0` means "the beginning of everything".
    public var inode: UInt64

    /// The byte offset just past the last line already seen.
    public var offset: UInt64

    /// The cursor as a string: `<inode-hex>-<offset>`.
    public var token: String {
        "\(String(inode, radix: 16))-\(offset)"
    }
}
