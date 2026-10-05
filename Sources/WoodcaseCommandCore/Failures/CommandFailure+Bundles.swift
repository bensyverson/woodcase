//
//  CommandFailure+Bundles.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

extension CommandFailure {
    /// Maps a refused conversion between a bare `.pen` and a bundle: the wrong kind of
    /// document is a usage error (2), a taken destination a conflict (3).
    ///
    /// - Parameter error: The refusal.
    /// - Returns: The failure, its message ending in the command that helps.
    static func describing(_ error: PenBundleError) -> CommandFailure {
        switch error {
        case let .alreadyBundled(url):
            CommandFailure(
                message: "\(url.path) is already the document of a bundle — run the verb on the bundle itself.",
                exitCode: .usage
            )
        case let .notABundle(url):
            CommandFailure(
                message: "\(url.path) is a bare .pen file, not a .umbra bundle. "
                    + "`woodcase bundle \(url.path)` converts it first.",
                exitCode: .usage
            )
        case let .destinationExists(url):
            CommandFailure(
                message: "\(url.path) already exists, and nothing is overwritten. Move it aside, or choose another place.",
                exitCode: .conflict
            )
        }
    }
}
