//
//  PenFileError.swift
//  Woodcase
//

import Foundation

/// Errors thrown while this package works with a file on disk — a .pen file under a
/// ``PenFileTransaction``, or the ``ActivityLog`` that transaction appends to.
///
/// Every case names the file by URL, so a caller can print the path without
/// having to remember which one it asked for — and so that a failure to append to the
/// log is distinguishable from a failure to write the document. The cases divide cleanly along the
/// lines a command-line exit code cares about: ``cannotOpen(url:reason:)`` and
/// ``unreadable(url:reason:)`` mean *this file is not usable*, ``lockTimeout(url:timeout:)``
/// means *someone else has it*, and ``writeFailed(url:reason:)`` means *the edit
/// was made but could not be saved*.
///
/// The underlying `errno` string or ``PenParserError`` description is carried as
/// `reason` rather than as a nested error: the enum stays `Sendable` and `Hashable`,
/// which an untyped `Error` payload would forfeit.
public enum PenFileError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The file could not be opened — it does not exist, or the process cannot read
    /// (or, for a write transaction, write) it.
    ///
    /// - Parameters:
    ///   - url: The file the transaction was asked to open.
    ///   - reason: The system's description of the failure, from `strerror`.
    case cannotOpen(url: URL, reason: String)

    /// The file opened but its contents are not a readable .pen document.
    ///
    /// - Parameters:
    ///   - url: The file that was read.
    ///   - reason: The ``PenParserError`` description explaining what failed.
    case unreadable(url: URL, reason: String)

    /// Another process or task still held the advisory lock when the timeout expired.
    ///
    /// - Parameters:
    ///   - url: The file whose lock could not be taken.
    ///   - timeout: How long the transaction waited before giving up.
    case lockTimeout(url: URL, timeout: Duration)

    /// The edited document could not be written back.
    ///
    /// The original file is untouched: the new contents go to a temporary file in
    /// the same directory and only replace the original once they are complete.
    ///
    /// - Parameters:
    ///   - url: The file the transaction was writing.
    ///   - reason: The system's description of the failure.
    case writeFailed(url: URL, reason: String)

    /// The file this error is about.
    public var url: URL {
        switch self {
        case let .cannotOpen(url, _), let .unreadable(url, _),
             let .lockTimeout(url, _), let .writeFailed(url, _):
            url
        }
    }

    /// A `reason` fit to sit inside a one-line message.
    ///
    /// `String(describing:)` on a Cocoa error prints its domain, its code, its
    /// `UserInfo` dictionary and any error nested inside it — six lines of noise that a
    /// caller then prints on every failed write. Since ``description`` promises one
    /// line, the reason has to be one too: the localized sentence, flattened.
    ///
    /// - Parameter error: The failure to describe.
    /// - Returns: A single line, with no trailing punctuation of its own.
    public static func oneLineReason(_ error: any Error) -> String {
        var line = error.localizedDescription
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Callers punctuate; a localized sentence brings its own full stop, and two in a
        // row read as a typo.
        while line.hasSuffix(".") {
            line.removeLast()
        }
        return line
    }

    /// A one-line message naming the file and what went wrong.
    public var description: String {
        switch self {
        case let .cannotOpen(url, reason):
            "Cannot open \(url.path): \(reason)"
        case let .unreadable(url, reason):
            "\(url.path) is not a readable .pen document: \(reason)"
        case let .lockTimeout(url, timeout):
            "\(url.path) is locked by another process; gave up after \(timeout.formattedForMessages)"
        case let .writeFailed(url, reason):
            "Cannot write \(url.path): \(reason); the original file is unchanged"
        }
    }
}

private extension Duration {
    /// The duration as a short decimal number of seconds, for use in a message.
    var formattedForMessages: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%gs", seconds)
    }
}
