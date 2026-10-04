//
//  ViewerPresence+Presence.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

public extension ViewerPresence {
    /// Maps the library's ``Presence`` onto the viewer's payload.
    ///
    /// The payload is the page's contract and stays what it was before presence moved
    /// into the library: the same identities, order and counts, with files named by the
    /// viewer's ids instead of paths.
    ///
    /// - Parameters:
    ///   - presence: The library's snapshot.
    ///   - fileID: The viewer's id for a canonical path, or `nil` for a file the viewer
    ///     does not serve, which is then left out of that identity's files.
    init(_ presence: Presence, fileID: (String) -> String?) {
        self.init(identities: presence.identities.map { identity in
            Identity(
                name: identity.name,
                lastSeen: identity.lastSeen,
                events: identity.changes,
                files: identity.files.compactMap(fileID)
            )
        })
    }
}
