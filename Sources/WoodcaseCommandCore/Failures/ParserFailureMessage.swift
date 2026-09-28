//
//  ParserFailureMessage.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The sentence a verb prints when the file it was given will not parse.
///
/// ``PenParserError`` already says which file and what the decoder objected to — the
/// key path and the type it wanted. What it deliberately does not say is what to *do*,
/// because that depends on where the reader is standing. Standing at a shell, the
/// answer is a command:
///
/// ```
/// Cannot read /w/design.pen: not a .pen document — children[0].id should be a string
/// — check the file's JSON with `python3 -m json.tool /w/design.pen`.
/// ```
///
/// Every verb prints this one, whether it parsed the file itself or opened it under a
/// ``PenFileTransaction``, because the transaction lets the parser's own error through
/// rather than restating it.
enum ParserFailureMessage {
    /// The whole sentence: what could not be read, what was wrong with it, and the
    /// next command.
    ///
    /// - Parameter error: The parse failure, usually carrying the file it read.
    /// - Returns: One line for standard error.
    static func describe(_ error: PenParserError) -> String {
        "\(error) — \(remedy(for: error))"
    }

    // MARK: - Private

    /// What to do next, as a sentence naming a command to run.
    private static func remedy(for error: PenParserError) -> String {
        switch error {
        case .decodingFailed:
            "check the file's JSON\(inspect(error))."
        case .unsupportedVersion:
            "correct the \"version\" key\(inspect(error))."
        case let .differentMajor(_, version, _):
            "update Woodcase to a build that reads \(majorWildcard(version)), "
                + "or check the file's JSON\(inspect(error))."
        case let .fileReadFailed(url, _):
            "check the path — `ls \(url.deletingLastPathComponent().path)` lists what is there."
        case .invalidString:
            "pass the document's bytes as `Data`."
        }
    }

    /// `3.x` for `"3.0"`: the family of versions a build would have to read.
    private static func majorWildcard(_ version: String) -> String {
        PenFormatVersion(version).map { "\($0.major).x" } ?? version
    }

    /// ` with \`python3 -m json.tool <path>\``, for a failure that names a file.
    ///
    /// `json.tool` is the one reader guaranteed to be at hand that both validates the
    /// syntax — naming the line and column Foundation's decoder does not — and prints
    /// the tree, so the key the message named can be looked at. A failure with no file
    /// behind it gets no command, rather than one with a made-up path in it.
    private static func inspect(_ error: PenParserError) -> String {
        guard let path = error.url?.path else { return "" }
        return " with `python3 -m json.tool \(path)`"
    }
}
