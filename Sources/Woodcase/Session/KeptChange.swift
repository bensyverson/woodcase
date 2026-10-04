//
//  KeptChange.swift
//  Woodcase
//

import Foundation

/// Another author's work an undo left in place rather than overwrite.
///
/// Undo keeps theirs: when taking back the local author's edit would destroy a later
/// edit by someone else, the session keeps that edit and reports it here, so the app
/// can say "Kept 1 change by claude".
public struct KeptChange: Friendly {
    /// Creates a report of kept work.
    ///
    /// - Parameters:
    ///   - key: The key the other author wrote.
    ///   - author: Who wrote it.
    public init(key: ChangeKey, author: Author) {
        self.key = key
        self.author = author
    }

    /// The key the other author wrote, which the undo left as they wrote it.
    public var key: ChangeKey

    /// Who wrote it.
    public var author: Author
}
