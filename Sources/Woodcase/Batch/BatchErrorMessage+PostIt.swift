//
//  BatchErrorMessage+PostIt.swift
//  Woodcase
//

import Foundation

/// The sentence for a refused write to a node's `metadata.woodcase`.
extension BatchErrorMessage {
    /// Describes a post-it metadata value the convention does not spell.
    ///
    /// With a close spelling the remedy is the corrected write, ready to paste; without
    /// one it points at the convention's table.
    ///
    /// - Parameters:
    ///   - key: The path written, such as `common.metadata.woodcase.state`.
    ///   - nodeID: The node written to.
    ///   - value: The rejected value, as JSON.
    ///   - accepted: The spellings the key takes.
    ///   - suggestion: The closest of them, when one is close.
    ///   - document: The document, for the node's name path.
    ///   - dialect: Which grammar the remedy is written in.
    /// - Returns: The sentence.
    static func postItMetadataRejected(
        _ key: String,
        on nodeID: String,
        value: String,
        accepted: [String],
        suggestion: String?,
        in document: EditableDocument,
        dialect: RemedyDialect
    ) -> String {
        let table = "the postit table of `woodcase schema` lists every key and spelling"
        let statement = """
        \(key) on \(name(nodeID, in: document)) takes \(oneOf(accepted)), but the value \
        given is \(value)
        """
        guard let suggestion else {
            return sentence(statement, batch: table, command: table, in: dialect)
        }
        return sentence(
            statement,
            batch: "did you mean `\"\(key)\":\"\(suggestion)\"`? \(table)",
            command: "did you mean `woodcase set \(dialect.file) \(nodeID) \(key)=\(suggestion)`? \(table)",
            in: dialect
        )
    }

    /// `a`, `a or b`, `a, b or c`.
    private static func oneOf(_ spellings: [String]) -> String {
        guard let last = spellings.last else { return "nothing" }
        let rest = spellings.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) or \(last)"
    }
}

extension BatchErrorMessage {
    /// Describes a `metadata.woodcase.spans` value that is not spans Woodcase can draw.
    ///
    /// - Parameters:
    ///   - nodeID: The node written to.
    ///   - reason: What is wrong, from ``PenTextSpans/WireError``.
    ///   - document: The document, for the node's name path.
    ///   - dialect: Which grammar the remedy is written in.
    /// - Returns: The sentence.
    static func textSpansRejected(
        on nodeID: String,
        reason: String,
        in document: EditableDocument,
        dialect: RemedyDialect
    ) -> String {
        let key = PenMetadata.WoodcaseKey.spans.propertyPath
        let shape = "spans take \(PenTextSpans.wireForm), offsets in UTF-16 units of text"
        let example = #"{"text":"Make this bold","runs":[{"start":10,"end":14,"fontWeight":"700"}]}"#
        return sentence(
            "\(key) on \(name(nodeID, in: document)) is not spans Woodcase can draw: \(reason)",
            batch: "\(shape), for example `\"\(key)\":\(example)`",
            command: "\(shape), for example `woodcase set \(dialect.file) \(nodeID) \(key)='\(example)'`",
            in: dialect
        )
    }
}
