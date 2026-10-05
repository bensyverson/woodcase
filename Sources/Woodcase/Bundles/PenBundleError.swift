//
//  PenBundleError.swift
//  Woodcase
//

import Foundation

/// Why a conversion between a bare `.pen` and a bundle was refused.
public enum PenBundleError: Error, Friendly, LocalizedError {
    /// The file to convert is already the document of a bundle.
    ///
    /// - Parameter url: The path given.
    case alreadyBundled(URL)

    /// The operation needs a bundle, and the path names a bare `.pen`.
    ///
    /// - Parameter url: The path given.
    case notABundle(URL)

    /// Something already exists where the operation would write.
    ///
    /// - Parameter url: The path that is taken.
    case destinationExists(URL)

    /// A sentence naming the path and what to do instead.
    public var errorDescription: String? {
        switch self {
        case let .alreadyBundled(url):
            "\(url.path) is already in a bundle."
        case let .notABundle(url):
            "\(url.path) is not a .umbra bundle."
        case let .destinationExists(url):
            "\(url.path) already exists."
        }
    }
}
