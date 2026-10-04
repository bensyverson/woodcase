//
//  ChangeLedger.swift
//  Woodcase
//

import Foundation

/// Who last wrote each ``ChangeKey`` of a session's document, and when.
///
/// "Has anyone else changed this since?" cannot be answered by a revision: a revision
/// is a content hash, with no order, and a value changed and changed back hashes the
/// same. So the session stamps every key an applied operation writes with its author
/// and the change's ``CommittedChange/sequence``, and an undo compares stamps: a key
/// whose stamp is newer than the edit being undone, by another author, is theirs to
/// keep.
///
/// The ledger lives only as long as the session. It is a value, so a checkpoint keeps a
/// copy and a rollback puts it back.
struct ChangeLedger: Friendly {
    /// One key's last write.
    struct Stamp: Friendly {
        /// Who wrote the key.
        var author: Author

        /// The sequence of the change that wrote it.
        var sequence: UInt64
    }

    /// Creates an empty ledger.
    init() {}

    /// Every key written so far, with its last write.
    private(set) var stamps: [ChangeKey: Stamp] = [:]

    /// The last write of a key.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: Its stamp, or `nil` if no change in this session wrote it.
    func stamp(for key: ChangeKey) -> Stamp? {
        stamps[key]
    }

    /// Records that a change wrote some keys.
    ///
    /// - Parameters:
    ///   - keys: The keys written.
    ///   - author: Who wrote them.
    ///   - sequence: The change's sequence.
    mutating func stamp(_ keys: some Sequence<ChangeKey>, by author: Author, at sequence: UInt64) {
        let stamp = Stamp(author: author, sequence: sequence)
        for key in keys {
            stamps[key] = stamp
        }
    }
}
