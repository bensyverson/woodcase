//
//  PenNoteBoard+Threading.swift
//  Woodcase
//

import Foundation

extension PenNoteBoard {
    /// Groups comment messages into threads by `replyTo`.
    ///
    /// - Parameters:
    ///   - messages: Every comment message in document order, with its metadata.
    ///   - resolves: Whether an anchor's node is still in the document.
    /// - Returns: The threads in the document order of their first messages, then the
    ///   threads whose first message is gone, in the order their first reply appears.
    static func threads(
        of messages: [(message: PenCommentThread.Message, metadata: PenMetadata)],
        resolving resolves: (String) -> Bool
    ) -> [PenCommentThread] {
        let firstIDs = Set(messages.filter { $0.message.replyTo == nil }.map(\.message.id))
        var replies: [String: [PenCommentThread.Message]] = [:]
        var orphanOrder: [String] = []
        for entry in messages {
            guard let target = entry.message.replyTo else { continue }
            if !firstIDs.contains(target), replies[target] == nil { orphanOrder.append(target) }
            replies[target, default: []].append(entry.message)
        }
        var threads: [PenCommentThread] = []
        for (message, metadata) in messages where message.replyTo == nil {
            let written = metadata[woodcase: .anchor]
            let anchor = written.flatMap(PenCommentThread.Anchor.init)
            let state = state(metadata[woodcase: .state])
            threads.append(PenCommentThread(
                id: message.id,
                state: state.state,
                unrecognizedState: state.unrecognized,
                anchor: anchor,
                placement: placement(written: written != nil, anchor: anchor, resolves: resolves),
                messages: [message] + inTimeOrder(replies[message.id] ?? [])
            ))
        }
        for id in orphanOrder {
            threads.append(PenCommentThread(
                id: id, state: nil, anchor: nil, placement: .unanchored, isMissingFirstMessage: true,
                messages: inTimeOrder(replies[id] ?? [])
            ))
        }
        return threads
    }

    /// A first message's state: the known spelling, or open with the spelling kept.
    private static func state(_ written: AnyCodable?) -> (state: PenPostIt.State, unrecognized: String?) {
        guard case let .string(text)? = written else { return (.open, nil) }
        guard let state = PenPostIt.State(rawValue: text) else { return (.open, text) }
        return (state, nil)
    }

    /// Where a thread sits, from its anchor and whether its node still resolves.
    private static func placement(
        written: Bool, anchor: PenCommentThread.Anchor?, resolves: (String) -> Bool
    ) -> PenCommentThread.Placement {
        guard let anchor else { return written ? .unreadable : .unanchored }
        guard let node = anchor.node else { return .canvas }
        return resolves(node) ? .node : .deletedNode
    }

    /// Replies ordered by `createdAt`.
    ///
    /// A reply with no time takes the time of the reply before it in the file, so it
    /// stays right after that reply rather than jumping to either end; replies with no
    /// times at all keep document order, the sort being stable.
    private static func inTimeOrder(_ replies: [PenCommentThread.Message]) -> [PenCommentThread.Message] {
        var last = Date.distantPast
        let keyed = replies.map { reply in
            if let date = reply.createdAt.flatMap(PenComment.date(createdAt:)) { last = date }
            return (reply: reply, time: last)
        }
        return keyed.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element.reply)
    }
}
