//
//  PenNoteBoard.swift
//  Woodcase
//

import Foundation

/// The notes, comment threads and prompts a document holds, read for listing.
///
/// What `woodcase notes`, `comments` and `prompts` print, so the decisions behind those
/// listings — what a comment is, how replies thread, which threads `--mentions` keeps —
/// live in the library, and an app or a script gets the same answers. Every metadata
/// key is read through ``PenMetadata/subscript(woodcase:)``, so old spellings read too.
///
/// - **Notes** are the plain `note` nodes that are not comment messages: post-its.
/// - **Threads** group the comment notes (`woodcase.type: comment`) by `woodcase.replyTo`
///   (``PenCommentThread``).
/// - **Prompts** are the `prompt` nodes, with where their run stands (decision 14).
///
/// Each row carries the node's revision and, for a note, its settled size, both from the
/// same settled read `tree` prints, so a listing taken straight after a write reports
/// what the file now renders.
///
/// ```swift
/// let board = try PenNoteBoard(document: document)
/// let mine = board.threads(PenNoteBoard.CommentQuery(mentions: "claude")) // open ones
/// let work = board.prompts(PenNoteBoard.PromptQuery(state: .queued))
/// ```
public struct PenNoteBoard: Friendly {
    /// The post-its, in document order.
    public var notes: [Note]

    /// The comment threads, in the document order of their first messages; threads whose
    /// first message is gone follow, in the order their first reply appears.
    public var threads: [PenCommentThread]

    /// The prompts, in document order.
    public var prompts: [Prompt]

    /// Reads a document's notes, threads and prompts.
    ///
    /// - Parameter document: The document to read; it is laid out once, for the notes'
    ///   settled sizes and every row's revision.
    /// - Throws: Whatever the settled tree read throws.
    public init(document: EditableDocument) throws {
        var notes: [Note] = []
        var prompts: [Prompt] = []
        var messages: [(message: PenCommentThread.Message, metadata: PenMetadata)] = []
        for row in try TreeView.rows(of: document) {
            guard let node = document.node(id: row.id) else { continue }
            let metadata = node.common.metadata ?? PenMetadata(type: nil)
            func string(_ key: PenMetadata.WoodcaseKey) -> String? {
                if case let .string(text)? = metadata[woodcase: key] { return text }
                return nil
            }
            switch node.kind {
            case let .note(data):
                let content = data.content.map(Self.text) ?? ""
                if string(.type) == PenPostIt.NoteType.comment.rawValue {
                    let markdown = PenNoteMarkdown(content)
                    messages.append((PenCommentThread.Message(
                        id: node.id, rev: row.rev, author: string(.author), replyTo: string(.replyTo),
                        createdAt: string(.createdAt).flatMap { PenComment.date(createdAt: $0) == nil ? nil : $0 },
                        content: content, firstLine: Self.firstLine(of: markdown), mentions: markdown.mentionedNames
                    ), metadata))
                } else {
                    notes.append(Note(
                        id: node.id, rev: row.rev, name: node.common.name, author: string(.author),
                        tint: string(.tint), size: row.rect.map { PenSize(width: $0.width, height: $0.height) },
                        content: content, firstLine: Self.firstLine(of: PenNoteMarkdown(content))
                    ))
                }
            case let .prompt(data):
                let content = data.content.map(Self.text) ?? ""
                prompts.append(Prompt(
                    id: node.id, rev: row.rev, name: node.common.name, state: string(.state),
                    requestedBy: string(.requestedBy), author: string(.author), model: data.model,
                    content: content, firstLine: Self.firstLine(of: PenNoteMarkdown(content))
                ))
            default:
                continue
            }
        }
        self.notes = notes
        self.prompts = prompts
        threads = Self.threads(of: messages, resolving: document.resolvesCommentAnchor)
    }

    // MARK: - Queries

    /// The notes a query keeps.
    ///
    /// - Parameter query: The filters.
    /// - Returns: The notes, in document order.
    public func notes(_ query: NoteQuery) -> [Note] {
        notes.filter { note in query.author.map { note.author == $0 } ?? true }
    }

    /// The threads a query keeps: every filter must hold.
    ///
    /// A thread mentions a name, or is an author's, when any of its messages does or is;
    /// its state is ``CommentQuery/effectiveState``. A thread whose first message is gone
    /// has no state, so a state filter other than ``CommentQuery/State/all`` leaves it out.
    ///
    /// - Parameter query: The filters.
    /// - Returns: The threads, in ``threads`` order.
    public func threads(_ query: CommentQuery) -> [PenCommentThread] {
        threads.filter { thread in
            guard query.mentions.map({ thread.mentions.contains($0) }) ?? true,
                  query.author.map({ thread.authors.contains($0) }) ?? true
            else { return false }
            switch query.effectiveState {
            case .all: return true
            case .open: return thread.state == .open
            case .resolved: return thread.state == .resolved
            }
        }
    }

    /// The prompts a query keeps: every filter must hold.
    ///
    /// - Parameter query: The filters.
    /// - Returns: The prompts, in document order.
    public func prompts(_ query: PromptQuery) -> [Prompt] {
        prompts.filter { prompt in
            guard query.requestedBy.map({ prompt.requestedBy == $0 }) ?? true else { return false }
            guard let state = query.state, state != .all else { return true }
            return prompt.state == state.rawValue
        }
    }

    // MARK: - Reading

    /// A content value as text: the literal, or a variable reference as `$name`.
    private static func text(_ value: PenValue<String>) -> String {
        switch value {
        case let .literal(text): text
        case let .variable(name): "$\(name)"
        }
    }

    /// The first line with words in it, syntax removed and list-marker tabs as spaces.
    private static func firstLine(of markdown: PenNoteMarkdown) -> String {
        let line = markdown.displayText
            .split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? ""
    }
}
