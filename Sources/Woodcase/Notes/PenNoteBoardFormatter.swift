//
//  PenNoteBoardFormatter.swift
//  Woodcase
//

import Foundation

/// Renders what ``PenNoteBoard`` reads: an aligned listing for reading, one row per
/// item, and the JSON reports for parsing.
///
/// Each listing opens with a header line carrying the document's revision and the count,
/// then a line naming the columns, laid out as `tree` lays out its rows
/// (the same aligned columns): the id is always the last field, so a row's address is its last
/// word even when its text has spaces. A missing value prints `-`. A note's or a
/// message's text is its first line, markdown removed.
///
/// ```text
/// rev 4f2a1b0c9d8e7f60  2 threads  3 messages
/// state     anchor       author  mentions  text                                id
/// open      Btn01 @12,4  ana     @claude   Should this be 44pt tall, @claude?  Cm01
///   reply   -            claude  @ana      Yes, per the HIG. @ana              Cm02
/// resolved  Card1 @0,0   ben     @claude   @claude rename Card to StatCard     Cm04
/// ```
///
/// In a comment listing the first message's row leads with the thread's state and each
/// reply's with `  reply`; a reply whose first message is gone leads with `⚠ orphan`
/// and its text says which message is missing.
public enum PenNoteBoardFormatter {
    // MARK: - Text

    /// The notes as an aligned listing: author, tint, settled size, first line, id.
    ///
    /// - Parameters:
    ///   - notes: The notes to list.
    ///   - revision: The document's revision.
    /// - Returns: The header line and the listing, with no trailing newline.
    public static func text(notes: [PenNoteBoard.Note], revision: String) -> String {
        var table = [["author", "tint", "size", "text", "id"]]
        for note in notes {
            let size = note.size.map { "\(TreeFormatter.number($0.width))×\(TreeFormatter.number($0.height))" }
            table.append([
                cell(note.author), cell(note.tint), cell(size), TreeFormatter.oneLine(note.firstLine), note.id,
            ])
        }
        return header(revision, count: notes.count, noun: "note") + "\n" + AlignedTable.text(table)
    }

    /// The threads as an aligned listing, one row per message: state (or `reply`),
    /// anchor, author, mentions, first line, id.
    ///
    /// - Parameters:
    ///   - threads: The threads to list.
    ///   - revision: The document's revision.
    /// - Returns: The header line and the listing, with no trailing newline.
    public static func text(threads: [PenCommentThread], revision: String) -> String {
        var table = [["state", "anchor", "author", "mentions", "text", "id"]]
        var messages = 0
        for thread in threads {
            for (index, message) in thread.messages.enumerated() {
                messages += 1
                let isFirst = index == 0 && !thread.isMissingFirstMessage
                let lead = isFirst ? (thread.state ?? "-") : thread.isMissingFirstMessage ? "⚠ orphan" : "  reply"
                var text = TreeFormatter.oneLine(message.firstLine)
                if thread.isMissingFirstMessage {
                    text = "⚠ no first message \(thread.id): " + text
                }
                table.append([
                    lead,
                    isFirst ? anchor(of: thread) : "-",
                    cell(message.author),
                    message.mentions.isEmpty ? "-" : message.mentions.map { "@\($0)" }.joined(separator: ","),
                    text,
                    message.id,
                ])
            }
        }
        let count = header(revision, count: threads.count, noun: "thread")
            + "  \(messages) \(messages == 1 ? "message" : "messages")"
        return count + "\n" + AlignedTable.text(table)
    }

    /// The prompts as an aligned listing: run state, who requested it, model, first
    /// line, id. A prompt never run shows `-` for its state.
    ///
    /// - Parameters:
    ///   - prompts: The prompts to list.
    ///   - revision: The document's revision.
    /// - Returns: The header line and the listing, with no trailing newline.
    public static func text(prompts: [PenNoteBoard.Prompt], revision: String) -> String {
        var table = [["state", "requestedBy", "model", "text", "id"]]
        for prompt in prompts {
            table.append([
                cell(prompt.state), cell(prompt.requestedBy), cell(prompt.model),
                TreeFormatter.oneLine(prompt.firstLine), prompt.id,
            ])
        }
        return header(revision, count: prompts.count, noun: "prompt") + "\n" + AlignedTable.text(table)
    }

    // MARK: - JSON

    /// Renders a report as pretty-printed JSON with sorted keys.
    ///
    /// - Parameter report: A ``PenNoteBoard/NotesReport``,
    ///   ``PenNoteBoard/CommentsReport`` or ``PenNoteBoard/PromptsReport``.
    /// - Returns: The JSON text.
    /// - Throws: Whatever `JSONEncoder` throws.
    public static func json(_ report: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(report), as: UTF8.self)
    }

    // MARK: - Cells

    /// The header line: the revision and how many items.
    private static func header(_ revision: String, count: Int, noun: String) -> String {
        "rev \(revision)  \(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// A value on one line, or `-` when there is none.
    private static func cell(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return TreeFormatter.oneLine(value)
    }

    /// A thread's anchor as `node @x,y`, `⚠ unreadable` for one that does not read, or `-`.
    private static func anchor(of thread: PenCommentThread) -> String {
        if thread.hasUnreadableAnchor { return "⚠ unreadable" }
        guard let anchor = thread.anchor, let node = anchor.node else { return "-" }
        guard let x = anchor.x, let y = anchor.y else { return node }
        return "\(node) @\(TreeFormatter.number(x)),\(TreeFormatter.number(y))"
    }
}
