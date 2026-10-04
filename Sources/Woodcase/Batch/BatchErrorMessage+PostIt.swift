//
//  BatchErrorMessage+PostIt.swift
//  Woodcase
//

import Foundation

/// The sentence for a refused write to a post-it's metadata.
extension BatchErrorMessage {
    /// Describes a post-it metadata value the convention does not spell.
    ///
    /// With a close spelling the remedy is the corrected write, ready to paste; without
    /// one it points at the convention's table.
    ///
    /// - Parameters:
    ///   - key: The path written, such as `common.metadata.kind`.
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
        \(key) on the post-it \(name(nodeID, in: document)) takes \(oneOf(accepted)), but the value \
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
