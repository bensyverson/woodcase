//
//  PenComment+Writing.swift
//  Woodcase
//

import Foundation

public extension PenComment {
    /// The anchor for a comment on a node, the address resolved to the id form stored.
    ///
    /// The anchor names the node by id, never by name, so a rename does not orphan the
    /// thread: a plain node by its id, a node inside a component instance by its expanded
    /// id path (`instance/child`, ``ResolvedNodeAddress/address``).
    ///
    /// - Parameters:
    ///   - address: Any address ``EditableDocument/resolve(_:tags:)-(String,_)`` takes.
    ///   - x: The point's horizontal offset from the node's top-left corner, in points.
    ///   - y: The point's vertical offset from the node's top-left corner, in points.
    ///   - document: The document the node is in.
    /// - Returns: The anchor.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` or
    ///   ``EditingError/ambiguousAddress(address:candidates:)``.
    static func anchor(
        on address: String, x: Double, y: Double, in document: EditableDocument
    ) throws -> PenCommentThread.Anchor {
        try PenCommentThread.Anchor(node: document.resolve(address).address, x: x, y: y)
    }

    /// Starts a thread: a root-level comment note, open, anchored, stamped.
    ///
    /// The note is unnamed — a message is addressed by its id, and a name shared by
    /// every message at the root would be a duplicate — and placed past every root, as
    /// `add` places a root that says nowhere, so it never lands on an artboard in Pen.
    ///
    /// - Parameters:
    ///   - content: The message, as markdown.
    ///   - anchor: What the thread is about: a node that resolves, or no node for a
    ///     page point.
    ///   - author: Who wrote it.
    ///   - date: When; written to the second, in UTC.
    ///   - id: The id to give the message, or `nil` to mint one.
    ///   - document: The document to write into.
    /// - Returns: The insert, with the new thread's id.
    /// - Throws: ``WriteError/emptyMessage``; ``EditingError/addressNotFound(address:nearMisses:)``
    ///   for an anchor node that does not resolve; ``EditingError/invalidNodeID(id:)`` or
    ///   ``EditingError/duplicateNodeID(id:)`` for an `id` that cannot be used.
    static func startThread(
        _ content: String,
        anchor: PenCommentThread.Anchor,
        author: String,
        at date: Date,
        id: String? = nil,
        in document: EditableDocument
    ) throws -> Write {
        if let node = anchor.node, !document.resolvesCommentAnchor(node) {
            throw EditingError.addressNotFound(address: node, nearMisses: [])
        }
        var metadata = stamped(author: author, at: date)
        metadata[woodcase: .state] = .string(PenPostIt.State.open.rawValue)
        metadata[woodcase: .anchor] = anchor.value
        let note = try message(content, metadata: metadata, id: id, in: document)
        return Write(operation: .insertNode(EditOperation.InsertNode(node: note)), threadID: note.id, messageID: note.id)
    }

    /// Replies to a thread: a root-level comment note naming the thread's first message.
    ///
    /// - Parameters:
    ///   - content: The message, as markdown.
    ///   - messageID: Any message of the thread — the first, or a reply, which stands for
    ///     its thread.
    ///   - author: Who wrote it.
    ///   - date: When; written to the second, in UTC.
    ///   - id: The id to give the reply, or `nil` to mint one.
    ///   - document: The document to write into.
    /// - Returns: The insert, with the thread's id and the reply's.
    /// - Throws: ``WriteError/notAComment(id:threads:)`` when `messageID` is not a comment
    ///   message; ``WriteError/emptyMessage``; an ``EditingError`` for an unusable `id`.
    static func reply(
        _ content: String,
        to messageID: String,
        author: String,
        at date: Date,
        id: String? = nil,
        in document: EditableDocument
    ) throws -> Write {
        let firstID = try threadID(of: messageID, in: document)
        var metadata = stamped(author: author, at: date)
        metadata[woodcase: .replyTo] = .string(firstID)
        let note = try message(content, metadata: metadata, id: id, in: document)
        return Write(operation: .insertNode(EditOperation.InsertNode(node: note)), threadID: firstID, messageID: note.id)
    }

    /// Resolves or reopens a thread: sets its first message's `woodcase.state`.
    ///
    /// The write is the one deep key, `common.metadata.woodcase.state`, which a session
    /// folds onto the message's metadata (``EditOperation/normalized(in:)``), so it merges
    /// per entry with another author's write to any other key and undoes alone.
    ///
    /// - Parameters:
    ///   - state: The state to set.
    ///   - messageID: Any message of the thread.
    ///   - document: The document to write into.
    /// - Returns: The write, or `nil` when the thread is already in `state` — a thread
    ///   with no state written is open.
    /// - Throws: ``WriteError/notAComment(id:threads:)`` or
    ///   ``WriteError/firstMessageMissing(threadID:reply:)``.
    static func setState(_ state: PenPostIt.State, of messageID: String, in document: EditableDocument) throws -> Write? {
        let firstID = try threadID(of: messageID, in: document)
        guard let first = document.node(id: firstID), isComment(first) else {
            throw WriteError.firstMessageMissing(threadID: firstID, reply: messageID)
        }
        switch first.common.metadata?[woodcase: .state] {
        case .string(state.rawValue)?: return nil
        case nil where state == .open: return nil
        default: break
        }
        let patch = EditOperation.SetProperties(
            nodeID: firstID, properties: [PenMetadata.WoodcaseKey.state.path: .string(state.rawValue)]
        )
        return Write(operation: .setProperties(patch), threadID: firstID, messageID: firstID)
    }

    /// The thread a message belongs to: the id of its first message — the reply's
    /// `replyTo`, or the message itself.
    ///
    /// - Parameters:
    ///   - messageID: Any comment message's id.
    ///   - document: The document holding it.
    /// - Returns: The first message's id. For a reply whose first message is gone, the id
    ///   it names.
    /// - Throws: ``WriteError/notAComment(id:threads:)`` when `messageID` names no comment
    ///   message, listing the threads there are.
    static func threadID(of messageID: String, in document: EditableDocument) throws -> String {
        guard let node = document.node(id: messageID), isComment(node) else {
            throw WriteError.notAComment(id: messageID, threads: threadIDs(in: document))
        }
        if case let .string(target)? = node.common.metadata?[woodcase: .replyTo] { return target }
        return messageID
    }

    // MARK: - Private

    /// A message's metadata: a comment, its author and its time.
    private static func stamped(author: String, at date: Date) -> PenMetadata {
        var metadata = PenMetadata(type: PenMetadata.woodcaseType)
        metadata[woodcase: .type] = .string(PenPostIt.NoteType.comment.rawValue)
        metadata[woodcase: .author] = .string(author)
        metadata[woodcase: .createdAt] = .string(createdAt(date))
        return metadata
    }

    /// A comment note, sized and placed at the root.
    private static func message(
        _ content: String, metadata: PenMetadata, id: String?, in document: EditableDocument
    ) throws -> PenNode {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WriteError.emptyMessage }
        let id = try id.map { try usable($0, in: document) } ?? PenID.generate(avoiding: Set(document.nodes.keys))
        let note = PenNode(
            id: id,
            common: PenNodeCommon(metadata: metadata),
            kind: .note(PenNode.NoteData(
                width: .fixed(PenPostIt.defaultSize), height: .fixed(PenPostIt.defaultSize), content: .literal(content)
            ))
        )
        return BatchApplier.placedAtRoot(note, in: document, coordinates: .authored)
    }

    /// A caller's id, refused when it is malformed or taken.
    private static func usable(_ id: String, in document: EditableDocument) throws -> String {
        guard PenID.isValid(id) else { throw EditingError.invalidNodeID(id: id) }
        guard document.node(id: id) == nil else { throw EditingError.duplicateNodeID(id: id) }
        return id
    }

    /// Whether a node is a comment message.
    private static func isComment(_ node: PenNode) -> Bool {
        guard case .note = node.kind else { return false }
        return node.common.metadata?[woodcase: .type] == .string(PenPostIt.NoteType.comment.rawValue)
    }

    /// The first messages in the document, in document order.
    private static func threadIDs(in document: EditableDocument) -> [String] {
        var ids: [String] = []
        func visit(_ id: String) {
            if let node = document.node(id: id), isComment(node), node.common.metadata?[woodcase: .replyTo] == nil {
                ids.append(id)
            }
            document.childIDs(of: id).forEach(visit)
        }
        document.rootOrder.forEach(visit)
        return ids
    }
}
