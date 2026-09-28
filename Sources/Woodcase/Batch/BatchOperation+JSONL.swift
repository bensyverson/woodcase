//
//  BatchOperation+JSONL.swift
//  Woodcase
//

import Foundation

public extension BatchOperation {
    /// Decodes a batch file: one operation per line, in order.
    ///
    /// Blank lines are skipped so a hand-written file can breathe, but a line
    /// with any content must be a complete JSON object — a batch is JSONL, not
    /// pretty-printed JSON. The line number in a thrown error is 1-based, which
    /// is what an editor and `wc -l` agree on; ``BatchLineResult/line`` is the
    /// 0-based index into the decoded array.
    ///
    /// - Parameter text: The contents of a `.jsonl` batch file.
    /// - Returns: The operations, in file order.
    /// - Throws: ``BatchError/malformedLine(line:reason:)`` naming the line that
    ///   would not decode and what was wrong with it.
    static func decodeJSONL(_ text: String) throws -> [BatchOperation] {
        let decoder = JSONDecoder()
        var operations: [BatchOperation] = []

        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            do {
                try operations.append(decoder.decode(BatchOperation.self, from: Data(line.utf8)))
            } catch {
                throw BatchError.malformedLine(line: offset + 1, reason: reason(for: error, line: line))
            }
        }
        return operations
    }

    /// The reason a line failed to decode.
    ///
    /// A line that ``isMultiLineFragment(_:)`` recognises never comes from a
    /// hand-written batch — every whole operation is one JSON object, so it always
    /// starts with `{` — so it is almost always one line of a pretty-printed,
    /// multi-line object pasted in by mistake. That earns its own sentence naming the
    /// actual shape wanted, rather than the JSON decoder's generic complaint about the
    /// fragment it was handed.
    ///
    /// - Parameters:
    ///   - error: What the JSON decoder threw.
    ///   - line: The trimmed line that failed, for the fragment check.
    /// - Returns: The reason clause of ``BatchError/malformedLine(line:reason:)``'s
    ///   sentence. "it" rather than "the line": the sentence this lands in has already
    ///   said which line — "line 3 is not a batch operation: …".
    private static func reason(for error: any Error, line: String) -> String {
        guard isMultiLineFragment(line) else {
            return DecodingReason.describe(error, root: "it")
        }
        return "it is one line of a multi-line, pretty-printed JSON object, and a batch takes one op per line"
    }

    /// Whether a line looks like one line of an object that spans several, rather than
    /// a whole operation on its own.
    ///
    /// A real batch line is always a complete JSON object, so it always starts with
    /// `{`. `{` or `}` alone, or a line that opens with a quoted key, is what
    /// pretty-printing a single operation across several lines looks like split back
    /// apart by a naive line-by-line paste.
    ///
    /// - Parameter line: The trimmed line to check.
    /// - Returns: Whether the line is almost certainly a fragment, not a whole op.
    private static func isMultiLineFragment(_ line: String) -> Bool {
        line == "{" || line == "}" || line.hasPrefix("\"")
    }

    /// Encodes operations back to a batch file, one line each.
    ///
    /// The result decodes to an equal array, so a report can be written beside
    /// the batch that produced it.
    ///
    /// - Parameter operations: The operations to write.
    /// - Returns: The batch as JSONL, without a trailing newline.
    /// - Throws: Whatever `JSONEncoder` throws for a value it cannot represent.
    static func encodeJSONL(_ operations: [BatchOperation]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try operations
            .map { try String(decoding: encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
    }
}
