//
//  PostItConventionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The post-it convention, read through the public API alone: a note whose
/// `metadata.type` is `postit` carries a typed kind, state, author, tint and the rest.
/// See `project/2026-10-04-post-it-design.md`, Convention.
struct PostItConventionTests {
    /// A note carrying the given metadata object, parsed from a file.
    private func note(metadata: String?) throws -> PenNode {
        let metadataLine = metadata.map { #", "metadata": \#($0)"# } ?? ""
        let json = """
        { "version": "2.20", "children": [
          { "id": "Nte01", "name": "Sticky", "type": "note", "content": "hi"\(metadataLine) }
        ] }
        """
        return try #require(PenParser.parse(json).children.first)
    }

    @Test("Kind, state, author and tint read as typed values")
    func readsTypedValues() throws {
        let node = try note(metadata: """
        { "type": "postit", "kind": "question", "state": "resolved", "author": "ana",
          "leaf": "pODcm0", "stage": "Capture", "tint": "#A5D6A7", "copiedFrom": "claude" }
        """)

        let postIt = try #require(PenPostIt.Metadata(node))

        #expect(postIt.kind == .valid(.question))
        #expect(postIt.state == .valid(.resolved))
        #expect(postIt.author == "ana")
        #expect(postIt.leaf == "pODcm0")
        #expect(postIt.stage == "Capture")
        #expect(postIt.tint == .valid(PenHexColor(red: 0xA5, green: 0xD6, blue: 0xA7)))
        #expect(postIt.copiedFrom == "claude")
    }

    @Test("Absent keys read as nil")
    func absentKeysAreNil() throws {
        let postIt = try #require(PenPostIt.Metadata(note(metadata: #"{ "type": "postit" }"#)))

        #expect(postIt.kind == nil)
        #expect(postIt.state == nil)
        #expect(postIt.author == nil)
        #expect(postIt.tint == nil)
        #expect(postIt.copiedFrom == nil)
    }

    @Test("A misspelled or malformed value reads as unrecognized, keeping what the file wrote")
    func misspellingsReadAsUnrecognized() throws {
        let node = try note(metadata: """
        { "type": "postit", "kind": "questoin", "state": "Closed", "tint": "yellow" }
        """)

        let postIt = try #require(PenPostIt.Metadata(node))

        #expect(postIt.kind == .unrecognized("questoin"))
        #expect(postIt.state == .unrecognized("Closed"))
        #expect(postIt.tint == .unrecognized("yellow"))
        #expect(postIt.kind?.value == nil)
    }

    @Test("A tint in a hex form other than #RRGGBB reads as unrecognized")
    func tintMustBeSixDigits() throws {
        for tint in ["#FF0", "#FFF59D80", "FFF59D"] {
            let postIt = try #require(PenPostIt.Metadata(note(metadata: #"{ "type": "postit", "tint": "\#(tint)" }"#)))
            #expect(postIt.tint == .unrecognized(tint), "\(tint) read as \(String(describing: postIt.tint))")
        }
    }

    @Test("A node whose metadata is not a post-it's has no post-it metadata")
    func nonPostItIsNil() throws {
        #expect(try PenPostIt.Metadata(note(metadata: nil)) == nil)
        #expect(try PenPostIt.Metadata(note(metadata: #"{ "type": "component", "kind": "question" }"#)) == nil)
    }

    @Test("The convention's keys and spellings are public and typed")
    func keysAndSpellings() {
        #expect(PenPostIt.typeValue == "postit")
        #expect(PenPostIt.Key.allCases.map(\.rawValue) == [
            "type", "kind", "state", "author", "leaf", "stage", "tint", "copiedFrom",
        ])
        #expect(PenPostIt.Kind.allCases.map(\.rawValue) == ["question", "answer", "reference"])
        #expect(PenPostIt.State.allCases.map(\.rawValue) == ["open", "resolved"])
        #expect(PenPostIt.Key.kind.spellings == ["question", "answer", "reference"])
        #expect(PenPostIt.Key.author.spellings.isEmpty)
    }
}
