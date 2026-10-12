//
//  PenCommentWriteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Writing comments through the library: starting a thread, replying, and resolving,
/// so neither an agent nor Penumbra writes the comment keys by hand. Penumbra's notes
/// design rev 2, decision 8 and Ben's session 12 rulings under it.
struct PenCommentWriteTests {
    /// 2026-10-11T20:41:07Z.
    private let moment = Date(timeIntervalSince1970: 1_791_751_267)

    private func document(_ fixture: String = "notes-comments-prompts") throws -> EditableDocument {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "pen", subdirectory: "Fixtures"))
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func thread(_ id: String, in document: EditableDocument) throws -> PenCommentThread {
        try #require(PenNoteBoard(document: document).threads.first { $0.id == id })
    }

    // MARK: - createdAt

    @Test("createdAt is ISO 8601 in UTC, to the second")
    func createdAtForm() {
        #expect(PenComment.createdAt(moment) == "2026-10-11T20:41:07Z")
        #expect(PenComment.createdAt(moment.addingTimeInterval(0.75)) == "2026-10-11T20:41:07Z")
    }

    @Test("Only the UTC form with seconds reads as a time")
    func createdAtParsing() {
        #expect(PenComment.date(createdAt: "2026-10-11T20:41:07Z") == moment)
        for malformed in [
            "2026-10-11T20:41:07+02:00", "2026-10-11T20:41:07.5Z", "2026-10-11 20:41:07Z",
            "2026-10-11T20:41Z", "2026-13-11T20:41:07Z", "2026-02-30T10:00:00Z", "yesterday",
        ] {
            #expect(PenComment.date(createdAt: malformed) == nil, "\(malformed) read as a time")
        }
    }

    @Test("An authored createdAt that is not ISO 8601 UTC is refused, naming the form")
    func createdAtValidated() throws {
        let bad: [String: AnyCodable] = ["type": "woodcase", "woodcase": ["createdAt": "2026-10-11T20:41:07+02:00"]]
        let violation = try #require(PenPostIt.violation(in: bad, comparedTo: nil))
        #expect(violation.key == .createdAt)
        #expect(violation.accepted == [PenComment.createdAtForm])

        let number: [String: AnyCodable] = ["type": "woodcase", "woodcase": ["createdAt": 1_791_751_267]]
        #expect(PenPostIt.violation(in: number, comparedTo: nil)?.key == .createdAt)

        let good: [String: AnyCodable] = ["type": "woodcase", "woodcase": ["createdAt": "2026-10-11T20:41:07Z"]]
        #expect(PenPostIt.violation(in: good, comparedTo: nil) == nil)
    }

    // MARK: - Starting a thread

    @Test("An anchor on a node stores its id; on an instance child, the expanded id path")
    func anchorOnNode() throws {
        let document = try document("addressing")
        #expect(try PenComment.anchor(on: "Dashboard/Header/Title", x: 3, y: 2, in: document)
            == PenCommentThread.Anchor(node: "Ttl01", x: 3, y: 2))
        #expect(try PenComment.anchor(on: "Dashboard/Body/Nav/Label", x: 1, y: 1, in: document)
            == PenCommentThread.Anchor(node: "Nav01/Lbl01", x: 1, y: 1))
    }

    @Test("An anchor on a node that is not there is refused with the near misses")
    func anchorOnMissingNode() throws {
        let document = try document("addressing")
        #expect(throws: EditingError.self) {
            try PenComment.anchor(on: "Dashboard/Nope", x: 0, y: 0, in: document)
        }
    }

    @Test("Starting a thread writes a root comment note: author, createdAt, open, anchor")
    func startThread() throws {
        let document = try document()
        let write = try PenComment.startThread(
            "Is this **right**?", anchor: PenCommentThread.Anchor(node: "Btn01", x: 12, y: 4),
            author: "claude", at: moment, in: document
        )
        #expect(write.threadID == write.messageID)
        try document.apply(write.operation)

        #expect(document.rootOrder.contains(write.messageID))
        let thread = try thread(write.messageID, in: document)
        #expect(thread.state == .open)
        #expect(thread.anchor == PenCommentThread.Anchor(node: "Btn01", x: 12, y: 4))
        #expect(thread.placement == .node)
        #expect(thread.messages.map(\.author) == ["claude"])
        #expect(thread.messages.first?.createdAt == "2026-10-11T20:41:07Z")
        #expect(thread.messages.first?.content == "Is this **right**?")
    }

    @Test("A thread with no node is on the canvas, at page coordinates")
    func canvasThread() throws {
        let document = try document()
        let write = try PenComment.startThread(
            "Room for a legend here", anchor: PenCommentThread.Anchor(node: nil, x: 900, y: 40),
            author: "ana", at: moment, in: document
        )
        try document.apply(write.operation)

        let thread = try thread(write.messageID, in: document)
        #expect(thread.anchor == PenCommentThread.Anchor(node: nil, x: 900, y: 40))
        #expect(thread.placement == .canvas)
    }

    @Test("A chosen id is kept; one already in use is refused")
    func chosenID() throws {
        let document = try document()
        let write = try PenComment.startThread(
            "Hi", anchor: PenCommentThread.Anchor(node: nil, x: 0, y: 0), author: "ana", at: moment, id: "CmNew",
            in: document
        )
        #expect(write.messageID == "CmNew")
        #expect(throws: EditingError.duplicateNodeID(id: "Cm01")) {
            try PenComment.startThread(
                "Hi", anchor: PenCommentThread.Anchor(node: nil, x: 0, y: 0), author: "ana", at: moment, id: "Cm01",
                in: document
            )
        }
    }

    // MARK: - Replying

    @Test("A reply to a reply still threads under the first message, with author and createdAt")
    func replyToReply() throws {
        let document = try document()
        let write = try PenComment.reply("Will do.", to: "Cm02", author: "claude", at: moment, in: document)
        #expect(write.threadID == "Cm01")
        try document.apply(write.operation)

        let thread = try thread("Cm01", in: document)
        let reply = try #require(thread.messages.last)
        #expect(reply.id == write.messageID)
        #expect(reply.replyTo == "Cm01")
        #expect(reply.author == "claude")
        #expect(reply.createdAt == "2026-10-11T20:41:07Z")
    }

    @Test("A reply to something that is not a comment is refused with the threads there are")
    func replyToNonComment() throws {
        let document = try document()
        for id in ["Zz999", "Nte01", "Btn01"] {
            #expect(throws: PenComment.WriteError.notAComment(id: id, threads: ["Cm01", "Cm04", "Cm06"])) {
                try PenComment.reply("Hi", to: id, author: "ana", at: moment, in: document)
            }
        }
        let message = PenComment.WriteError.notAComment(id: "Zz999", threads: ["Cm01", "Cm04"]).message
        #expect(message.contains("Zz999"))
        #expect(message.contains("Cm01, Cm04"))
        #expect(message.contains("woodcase comments"))
    }

    // MARK: - Resolving

    @Test("Resolving sets the first message's state, even given a reply; reopening sets it back")
    func resolveAndReopen() throws {
        let document = try document()
        let resolve = try #require(try PenComment.setState(.resolved, of: "Cm02", in: document))
        #expect(resolve.threadID == "Cm01")
        #expect(resolve.messageID == "Cm01")
        try document.apply(resolve.operation.normalized(in: document))
        #expect(try thread("Cm01", in: document).state == .resolved)

        let reopen = try #require(try PenComment.setState(.open, of: "Cm01", in: document))
        try document.apply(reopen.operation.normalized(in: document))
        #expect(try thread("Cm01", in: document).state == .open)
    }

    @Test("Setting the state a thread already has writes nothing")
    func stateAlreadySet() throws {
        let document = try document()
        #expect(try PenComment.setState(.resolved, of: "Cm04", in: document) == nil)
        #expect(try PenComment.setState(.open, of: "Cm01", in: document) == nil)
    }

    @Test("Resolving keeps every other key on the first message")
    func resolveKeepsKeys() throws {
        let document = try document()
        let write = try #require(try PenComment.setState(.resolved, of: "Cm01", in: document))
        try document.apply(write.operation.normalized(in: document))
        let metadata = try #require(document.node(id: "Cm01")?.common.metadata)
        #expect(metadata[woodcase: .author] == .string("ana"))
        #expect(metadata[woodcase: .anchor] != nil)
        #expect(metadata[woodcase: .type] == .string("comment"))
    }

    @Test("A resolve writes one metadata entry, so it merges with a write to another made after it was built")
    func resolveMergesPerEntry() throws {
        let session = try DocumentSession(
            document: document().materialize(), author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")),
            file: nil
        )
        let resolve = try #require(try PenComment.setState(.resolved, of: "Cm01", in: session.document))
        #expect(resolve.operation == .setProperties(EditOperation.SetProperties(
            nodeID: "Cm01", properties: [PenMetadata.WoodcaseKey.state.path: "resolved"]
        )))

        try session.submit(.local(LocalEdit(operations: [.setProperties(EditOperation.SetProperties(
            nodeID: "Cm01", properties: [PenMetadata.WoodcaseKey.leaf.path: "Wq5asV"]
        ))])))
        try session.submit(.local(LocalEdit(operations: [resolve.operation])))

        let metadata = try #require(session.document.node(id: "Cm01")?.common.metadata)
        #expect(metadata[woodcase: .state] == .string("resolved"))
        #expect(metadata[woodcase: .leaf] == .string("Wq5asV"))
        #expect(metadata[woodcase: .anchor] != nil)
    }

    @Test("Resolving a thread whose first message is gone is refused")
    func resolveOrphan() throws {
        let document = try document()
        #expect(throws: PenComment.WriteError.firstMessageMissing(threadID: "Gone1", reply: "Cm07")) {
            try PenComment.setState(.resolved, of: "Cm07", in: document)
        }
    }
}
