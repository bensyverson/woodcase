//
//  BatchErrorMessage+DocumentProperties.swift
//  Woodcase
//

import Foundation

/// The sentences for a refused ``EditOperation/setDocumentProperties(_:)``.
///
/// No verb writes the document root's own properties — a diff and undo do — so these
/// teach the vocabulary rather than a command.
extension BatchErrorMessage {
    /// The root's keys, as a remedy lists them.
    private static var documentKeys: String {
        let modeled = DocumentPropertyCodec.modeledKeys.sorted().map { "`\($0)`" }.joined(separator: ", ")
        return "\(modeled) or `\(DocumentPropertyCodec.extrasPrefix)<key>` for a root key the format does not model"
    }

    /// Describes a key that is not a document property.
    ///
    /// - Parameters:
    ///   - key: The key as written.
    ///   - dialect: Which grammar the remedy is written in.
    /// - Returns: The sentence.
    static func unknownDocumentProperty(_ key: String, in dialect: RemedyDialect) -> String {
        let remedy = "the document root takes \(documentKeys)"
        return sentence(
            "\(key) is not a property of the document root",
            batch: remedy,
            command: remedy,
            in: dialect
        )
    }

    /// Describes a document property value of the wrong shape.
    ///
    /// - Parameters:
    ///   - key: The key as written.
    ///   - expected: The shape the key takes.
    ///   - actual: The shape the value had.
    ///   - dialect: Which grammar the remedy is written in.
    /// - Returns: The sentence.
    static func documentPropertyTypeMismatch(
        _ key: String,
        expected: String,
        actual: String,
        in dialect: RemedyDialect
    ) -> String {
        let remedy = "write `\(key)` as \(expected)"
        return sentence(
            "the document's \(key) takes \(expected), but the value given is \(actual)",
            batch: remedy,
            command: remedy,
            in: dialect
        )
    }
}
