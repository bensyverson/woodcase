//
//  PenParserError.swift
//  Woodcase
//

import Foundation

/// Errors specific to .pen document parsing.
///
/// Every case that can name the file it was reading does: ``PenParser/parse(contentsOf:diagnostics:)``
/// attaches the URL on the way out, so a caller that prints the error prints a path,
/// and a caller that wants to build its own sentence reads ``url``. Parsing bytes with
/// no file behind them — ``PenParser/parse(_:diagnostics:)-(Data,_)`` — leaves it `nil`.
public enum PenParserError: Error, CustomStringConvertible {
    /// The input data could not be decoded as a valid .pen document.
    ///
    /// - Parameters:
    ///   - url: The file the bytes came from, or `nil` when they came from memory.
    ///   - underlying: What the decoder threw — usually a `DecodingError`, which
    ///     ``description`` reads the key path and expected type out of.
    case decodingFailed(url: URL?, underlying: Error)

    /// The input string could not be converted to UTF-8 data.
    case invalidString

    /// The file at the given URL could not be read.
    case fileReadFailed(url: URL, underlying: Error)

    /// The document's `version` is not a `major.minor` number at all — an empty
    /// string, a word, three components, or not a string.
    ///
    /// A well-formed version of another major is ``differentMajor(url:version:reason:)``
    /// instead, and only when the document does not read.
    ///
    /// - Parameters:
    ///   - url: The file that declared it, or `nil` when the bytes came from memory.
    ///   - version: The version as the document declared it.
    case unsupportedVersion(url: URL?, version: String)

    /// The document declares another major version, and does not read as a document
    /// of the major this build models.
    ///
    /// A different major that *does* read — a `children` array of nodes with ids and
    /// types, at least one of a type this build models, all decoding cleanly — is
    /// not an error: it opens read-only, with a warning. This is the other case.
    ///
    /// - Parameters:
    ///   - url: The file that declared it, or `nil` when the bytes came from memory.
    ///   - version: The version as the document declared it.
    ///   - reason: The first thing that did not read, naming its key path.
    case differentMajor(url: URL?, version: String, reason: String)

    /// The file this error is about, when it was read from one.
    public var url: URL? {
        switch self {
        case let .decodingFailed(url, _), let .unsupportedVersion(url, _),
             let .differentMajor(url, _, _):
            url
        case let .fileReadFailed(url, _):
            url
        case .invalidString:
            nil
        }
    }

    /// A one-line message naming the file, when there is one, and what was wrong with it.
    ///
    /// The remedy is deliberately absent: what to *do* about an unreadable document
    /// depends on where the reader is standing, so the command line adds its own.
    public var description: String {
        "Cannot read \(subject): \(clause)"
    }

    /// The failure with `url` filled in, for a parse that knows which file it read.
    ///
    /// A case that already names a file, or that never had one to name, is returned
    /// unchanged — the innermost throw site wins, which is what makes it safe to call
    /// this on the way out of a nested parse.
    ///
    /// - Parameter url: The file the bytes came from.
    /// - Returns: The same failure, naming the file.
    func attaching(_ url: URL?) -> PenParserError {
        guard let url, self.url == nil else { return self }
        switch self {
        case let .decodingFailed(_, underlying):
            return .decodingFailed(url: url, underlying: underlying)
        case let .unsupportedVersion(_, version):
            return .unsupportedVersion(url: url, version: version)
        case let .differentMajor(_, version, reason):
            return .differentMajor(url: url, version: version, reason: reason)
        case .invalidString, .fileReadFailed:
            return self
        }
    }

    /// What the message calls the thing that could not be read.
    private var subject: String {
        url?.path ?? "the .pen input"
    }

    /// What went wrong, as a clause the subject introduces.
    private var clause: String {
        switch self {
        case let .decodingFailed(_, underlying):
            "not a .pen document — \(DecodingReason.describe(underlying))"
        case .invalidString:
            "the string is not valid UTF-8"
        case let .fileReadFailed(_, underlying):
            underlying.localizedDescription
        case let .unsupportedVersion(_, version):
            "its \"version\" value \"\(version)\" is not a major.minor format version"
        case let .differentMajor(_, version, reason):
            "its format version \"\(version)\" is a different major version from the "
                + "\(PenDocument.currentFormatVersion) this build models, and it does not read as a "
                + "\(PenFormatVersion.current.major).x document: \(reason)"
        }
    }
}
