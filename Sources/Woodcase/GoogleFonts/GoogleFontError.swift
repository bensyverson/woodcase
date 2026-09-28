//
//  GoogleFontError.swift
//  Woodcase
//

import Foundation

/// Errors that can occur during Google Fonts resolution.
public enum GoogleFontError: Error, Sendable {
    /// The Google Fonts repository answered, and has no family by this name: every
    /// license directory returned 404.
    case familyNotFound(String)

    /// The family could not be fetched: the network was unreachable, or the server
    /// answered with an error other than 404. Says nothing about whether the family
    /// exists.
    case networkUnavailable(family: String, failure: RemoteFetchError)

    /// The METADATA.pb file could not be parsed.
    case metadataParseError(String)

    /// The requested weight is not available for the given font family.
    case weightNotAvailable(family: String, weight: Int)
}
