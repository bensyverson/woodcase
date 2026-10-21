//
//  PostItConventionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The post-it convention, read through the public API alone: a note's
/// `metadata.woodcase` carries a typed type, state, author, tint and the rest, and the
/// bare keys of a `type: postit` object are still read, the namespace winning. See
/// `project/2026-10-04-post-it-design.md`, Convention, as revised by
/// `../Penumbra/project/2026-10-11-notes-comments-and-spans.md`.
struct PostItConventionTests {
    /// A node of the given type carrying the given metadata object, parsed from a file.
    private func node(_ type: String = "note", metadata: String?) throws -> PenNode {
        let metadataLine = metadata.map { #", "metadata": \#($0)"# } ?? ""
        let json = """
        { "version": "2.20", "children": [
          { "id": "Nte01", "name": "Sticky", "type": "\(type)", "content": "hi"\(metadataLine) }
        ] }
        """
        return try #require(PenParser.parse(json).children.first)
    }

    @Test("Type, state, author and tint read as typed values from the namespace")
    func readsTypedValues() throws {
        let node = try node(metadata: """
        { "woodcase": { "type": "comment", "state": "resolved", "author": "ana", "leaf": "pODcm0",
          "stage": "Capture", "tint": "#A5D6A7", "copiedFrom": "claude",
          "anchor": { "node": "abc", "x": 4, "y": 8 }, "replyTo": "Nte00" } }
        """)

        let postIt = try #require(PenPostIt.Metadata(node))

        #expect(postIt.type == .valid(.comment))
        #expect(postIt.state == .valid(.resolved))
        #expect(postIt.author == "ana")
        #expect(postIt.leaf == "pODcm0")
        #expect(postIt.stage == "Capture")
        #expect(postIt.tint == .valid(PenHexColor(red: 0xA5, green: 0xD6, blue: 0xA7)))
        #expect(postIt.copiedFrom == "claude")
        #expect(postIt.anchor == .dictionary(["node": .string("abc"), "x": .int(4), "y": .int(8)]))
        #expect(postIt.replyTo == "Nte00")
    }

    @Test("The old bare keys of a type: postit object read the same, the namespace winning")
    func readsOldSpellings() throws {
        let node = try node(metadata: """
        { "type": "postit", "state": "open", "author": "ana", "tint": "#A5D6A7",
          "woodcase": { "state": "resolved" } }
        """)

        let postIt = try #require(PenPostIt.Metadata(node))

        #expect(postIt.type == .valid(.postit))
        #expect(postIt.state == .valid(.resolved))
        #expect(postIt.author == "ana")
        #expect(postIt.tint?.value == PenHexColor(red: 0xA5, green: 0xD6, blue: 0xA7))
    }

    @Test("Absent keys read as nil")
    func absentKeysAreNil() throws {
        let postIt = try #require(PenPostIt.Metadata(node(metadata: #"{ "woodcase": { "type": "postit" } }"#)))

        #expect(postIt.state == nil)
        #expect(postIt.author == nil)
        #expect(postIt.tint == nil)
        #expect(postIt.copiedFrom == nil)
        #expect(postIt.anchor == nil)
    }

    @Test("A misspelled or malformed value reads as unrecognized, keeping what the file wrote")
    func misspellingsReadAsUnrecognized() throws {
        let node = try node(metadata: """
        { "woodcase": { "type": "postti", "state": "Closed", "tint": "yellow" } }
        """)

        let postIt = try #require(PenPostIt.Metadata(node))

        #expect(postIt.type == .unrecognized("postti"))
        #expect(postIt.state == .unrecognized("Closed"))
        #expect(postIt.tint == .unrecognized("yellow"))
        #expect(postIt.state?.value == nil)
    }

    @Test("A tint in a hex form other than #RRGGBB reads as unrecognized")
    func tintMustBeSixDigits() throws {
        for tint in ["#FF0", "#FFF59D80", "FFF59D"] {
            let postIt = try #require(PenPostIt.Metadata(node(metadata: #"{ "woodcase": { "tint": "\#(tint)" } }"#)))
            #expect(postIt.tint == .unrecognized(tint), "\(tint) read as \(String(describing: postIt.tint))")
        }
    }

    @Test("Every note is a post-it, with or without metadata")
    func everyNoteIsAPostIt() throws {
        let postIt = try #require(PenPostIt.Metadata(node(metadata: nil)))

        #expect(postIt.type == nil)
        #expect(postIt.state == nil)
        #expect(try PenPostIt.Metadata(node(metadata: #"{ "type": "scratch", "kind": "question" }"#)) != nil)
    }

    @Test("Another node is a post-it only when its metadata says so")
    func otherNodesNeedTheConvention() throws {
        #expect(try PenPostIt.Metadata(node("frame", metadata: nil)) == nil)
        #expect(try PenPostIt.Metadata(node("frame", metadata: #"{ "type": "component", "state": "open" }"#)) == nil)
        #expect(try PenPostIt.Metadata(node("frame", metadata: #"{ "type": "postit" }"#)) != nil)
        #expect(try PenPostIt.Metadata(node("frame", metadata: ##"{ "woodcase": { "tint": "#FFFFFF" } }"##)) != nil)
    }

    @Test("A legacy kind is not part of the convention")
    func legacyKindIsNotRead() throws {
        let node = try node(metadata: #"{ "type": "postit", "kind": "question" }"#)

        #expect(PenMetadata.WoodcaseKey(rawValue: "kind") == nil)
        #expect(node.common.metadata?.extensions["kind"] == .string("question"))
    }

    /// Changed 2026-10-11 (leaf dbLtoJ): `requestedBy` joins the note keys, for a
    /// prompt's Run (notes design rev 2, decision 14). Changed 2026-10-11 (leaf qPPYTG):
    /// `createdAt` joins them, the time a comment message was written. Changed 2026-10-21
    /// (leaf YPi92I): `scale` joins them, the size of a note's look.
    @Test("The convention's keys and spellings are public and typed")
    func keysAndSpellings() {
        #expect(PenPostIt.NoteType.allCases.map(\.rawValue) == ["postit", "comment"])
        #expect(PenPostIt.State.allCases.map(\.rawValue) == ["open", "resolved"])
        #expect(PenPostIt.keys.map(\.rawValue) == [
            "type", "state", "author", "leaf", "stage", "tint", "copiedFrom", "anchor", "replyTo", "requestedBy",
            "createdAt", "fontFamily", "fontSize", "fontWeight", "fontStyle", "letterSpacing", "lineHeight",
            "textAlign", "textAlignVertical", "scale",
        ])
        #expect(PenMetadata.WoodcaseKey.type.spellings == ["postit", "comment"])
        #expect(PenMetadata.WoodcaseKey.state.spellings == ["open", "resolved"])
        #expect(PenMetadata.WoodcaseKey.author.spellings.isEmpty)
    }

    @Test("Comments and prompts still validate their state values")
    func commentAndPromptStatesValidate() throws {
        let note = PenNode.Kind.note(PenNode.NoteData())
        let comment: [String: AnyCodable] = ["woodcase": .dictionary(["type": .string("comment"), "state": .string("closed")])]
        let refused = try #require(PenPostIt.violation(in: comment, comparedTo: nil, on: note))
        #expect(refused.key == .state)
        #expect(refused.accepted == ["open", "resolved"])
        let resolved: [String: AnyCodable] = ["woodcase": .dictionary(["type": .string("comment"), "state": .string("resolved")])]
        #expect(PenPostIt.violation(in: resolved, comparedTo: nil, on: note) == nil)
        let prompt = PenNode.Kind.prompt(PenNode.PromptData())
        let open: [String: AnyCodable] = ["woodcase": .dictionary(["state": .string("open")])]
        #expect(PenPostIt.violation(in: open, comparedTo: nil, on: prompt)?.accepted == ["queued", "running", "done"])
    }
}
