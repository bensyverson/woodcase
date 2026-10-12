//
//  PenCommentThreadPlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Where a thread sits, its state as a type, and the order of its replies — what a
/// listing and Penumbra's Comments tab read off ``PenCommentThread``. Ben's session 12
/// rulings under decision 8: an anchor without a node is a canvas comment, and a thread
/// whose node is gone is listed as on a deleted node, never rewritten.
struct PenCommentThreadPlacementTests {
    /// A document holding the given root nodes, as JSON objects.
    private func board(_ roots: String) throws -> PenNoteBoard {
        let json = #"{"version":"2.20","children":[\#(roots)]}"#
        return try PenNoteBoard(document: EditableDocument(from: PenParser.parse(json)))
    }

    /// A comment note's JSON with the given `woodcase` keys.
    private func comment(_ id: String, _ keys: String, content: String = "Hi") -> String {
        #"{"type":"note","id":"\#(id)","content":"\#(content)","width":200,"height":80,"#
            + #""metadata":{"type":"woodcase","woodcase":{"type":"comment",\#(keys)}}}"#
    }

    private let frame = #"{"type":"frame","id":"Frm01","name":"Card","width":100,"height":100}"#

    // MARK: - Placement

    @Test("A thread whose node resolves is on that node")
    func onNode() throws {
        let thread = try #require(try board(frame + "," + comment("Cm01", #""anchor":{"node":"Frm01","x":1,"y":2}"#))
            .threads.first)
        #expect(thread.placement == .node)
    }

    @Test("A thread whose node is gone is on a deleted node, and its anchor is kept as written")
    func onDeletedNode() throws {
        let thread = try #require(try board(comment("Cm01", #""anchor":{"node":"Frm01","x":1,"y":2}"#)).threads.first)
        #expect(thread.placement == .deletedNode)
        #expect(thread.anchor == PenCommentThread.Anchor(node: "Frm01", x: 1, y: 2))
    }

    @Test("An anchor with no node is a canvas comment, not an unreadable one")
    func onCanvas() throws {
        let thread = try #require(try board(comment("Cm01", #""anchor":{"x":40,"y":60}"#)).threads.first)
        #expect(thread.placement == .canvas)
        #expect(thread.anchor == PenCommentThread.Anchor(node: nil, x: 40, y: 60))
    }

    @Test("An anchor that does not read is unreadable; no anchor is unanchored")
    func unreadableAndUnanchored() throws {
        let threads = try board(
            comment("Cm01", #""anchor":"Frm01""#) + "," + comment("Cm02", #""anchor":{"node":7}"#) + ","
                + comment("Cm03", #""anchor":{"x":"left"}"#) + "," + comment("Cm04", #""author":"ana""#)
        ).threads
        #expect(threads.map(\.placement) == [.unreadable, .unreadable, .unreadable, .unanchored])
    }

    @Test("A thread on an instance child is on a node while the child exists, deleted once it does not")
    func onInstanceChild() throws {
        let component = #"{"type":"frame","id":"Btn01","name":"Button","reusable":true,"#
            + #""children":[{"type":"text","id":"Lbl01","name":"Label","content":"Go"}]}"#
        let emptied = #"{"type":"frame","id":"Btn01","name":"Button","reusable":true,"children":[]}"#
        let instance = #"{"type":"ref","id":"Nav01","name":"Nav","ref":"Btn01"}"#
        let note = comment("Cm01", #""anchor":{"node":"Nav01/Lbl01","x":0,"y":0}"#)

        let present = try #require(try board([component, instance, note].joined(separator: ",")).threads.first)
        #expect(present.placement == .node)
        let removed = try #require(try board([emptied, instance, note].joined(separator: ",")).threads.first)
        #expect(removed.placement == .deletedNode)
    }

    // MARK: - State

    @Test("A thread's state is typed: open, resolved, and open when none is written")
    func typedState() throws {
        let threads = try board(
            comment("Cm01", #""state":"open""#) + "," + comment("Cm02", #""state":"resolved""#) + ","
                + comment("Cm03", #""author":"ana""#)
        ).threads
        #expect(threads.map(\.state) == [.open, .resolved, .open])
        #expect(threads.allSatisfy { $0.unrecognizedState == nil })
    }

    @Test("A misspelled state reads as open and keeps its spelling for the listing")
    func misspelledState() throws {
        let thread = try #require(try board(comment("Cm01", #""state":"reslved""#)).threads.first)
        #expect(thread.state == .open)
        #expect(thread.unrecognizedState == "reslved")
        #expect(try board(comment("Cm01", #""state":"reslved""#)).threads(PenNoteBoard.CommentQuery(state: .open))
            .count == 1)
    }

    // MARK: - Reply order

    @Test("Replies are ordered by createdAt when they carry one")
    func repliesByCreatedAt() throws {
        let thread = try #require(try board([
            comment("Cm01", #""createdAt":"2026-10-11T10:00:00Z""#),
            comment("Cm03", #""replyTo":"Cm01","createdAt":"2026-10-11T12:00:00Z""#),
            comment("Cm02", #""replyTo":"Cm01","createdAt":"2026-10-11T11:00:00Z""#),
        ].joined(separator: ",")).threads.first)
        #expect(thread.messages.map(\.id) == ["Cm01", "Cm02", "Cm03"])
        #expect(thread.messages.map(\.createdAt) == [
            "2026-10-11T10:00:00Z", "2026-10-11T11:00:00Z", "2026-10-11T12:00:00Z",
        ])
    }

    @Test("A reply without a time stays after the reply it follows in the file")
    func untimedReplyFollowsItsPredecessor() throws {
        let thread = try #require(try board([
            comment("Cm01", #""author":"ana""#),
            comment("Cm04", #""replyTo":"Cm01","createdAt":"2026-10-11T12:00:00Z""#),
            comment("Cm05", #""replyTo":"Cm01""#),
            comment("Cm02", #""replyTo":"Cm01","createdAt":"2026-10-11T11:00:00Z""#),
            comment("Cm03", #""replyTo":"Cm01""#),
        ].joined(separator: ",")).threads.first)
        #expect(thread.messages.map(\.id) == ["Cm01", "Cm02", "Cm03", "Cm04", "Cm05"])
    }

    @Test("Without times, replies keep document order")
    func documentOrderWithoutTimes() throws {
        let thread = try #require(try board([
            comment("Cm01", #""author":"ana""#),
            comment("Cm03", #""replyTo":"Cm01""#),
            comment("Cm02", #""replyTo":"Cm01""#),
        ].joined(separator: ",")).threads.first)
        #expect(thread.messages.map(\.id) == ["Cm01", "Cm03", "Cm02"])
    }
}
