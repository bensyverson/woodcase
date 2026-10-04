//
//  PostItAuthoringTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An agent's write to a post-it's metadata is held to the convention: a misspelled kind
/// or state, a malformed tint or a non-string author is refused with a stable code and
/// the closest spelling, while a file that already holds one still opens and a write
/// that leaves it untouched passes. See `project/2026-10-04-post-it-design.md`,
/// Convention.
@MainActor
struct PostItAuthoringTests {
    private static let board = """
    {
      "version": "2.20",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 1000, "height": 1000, "layout": "none",
          "children": [
            { "id": "Nte01", "name": "Question", "type": "note", "content": "hi",
              "metadata": { "type": "postit", "kind": "question", "state": "open", "author": "claude" } },
            { "id": "Nte02", "name": "Legacy", "type": "note", "content": "hi",
              "metadata": { "type": "postit", "kind": "questoin", "state": "Closed", "tint": "yellow" } },
            { "id": "Nte03", "name": "Plain", "type": "note", "content": "hi",
              "metadata": { "type": "scratch", "kind": "anything" } }
          ]
        }
      ]
    }
    """

    private func makeDocument() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Self.board))
    }

    /// Runs a `set` and returns the refusal it raised, or `nil` when it applied.
    private func refusal(
        setting props: [String: AnyCodable],
        on address: String,
        in document: EditableDocument
    ) throws -> EditingError? {
        let target = try #require(NodeAddress(address))
        do {
            _ = try BatchApplier.applyOne(.set(BatchOperation.SetOp(target: target, props: props)), to: document)
            return nil
        } catch let error as EditingError {
            return error
        }
    }

    // MARK: - Refusals

    @Test("A misspelled kind is refused with a stable code and the closest spelling")
    func misspelledKindIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.kind": .string("questoin")], on: "Board/Question", in: makeDocument()
        ))

        #expect(error.code == "postItMetadataRejected")
        guard case let .postItMetadataRejected(nodeID, key, value, accepted, suggestion) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(nodeID == "Nte01")
        #expect(key == "common.metadata.kind")
        #expect(value == #""questoin""#)
        #expect(accepted == ["question", "answer", "reference"])
        #expect(suggestion == "question")
    }

    @Test("A misspelled state is refused with the closest spelling")
    func misspelledStateIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.state": .string("reslved")], on: "Board/Question", in: makeDocument()
        ))

        guard case let .postItMetadataRejected(_, key, _, accepted, suggestion) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(key == "common.metadata.state")
        #expect(accepted == ["open", "resolved"])
        #expect(suggestion == "resolved")
    }

    @Test("A value nowhere near a spelling is refused with no suggestion")
    func farValueHasNoSuggestion() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.kind": .string("zebra-crossing")], on: "Board/Question", in: makeDocument()
        ))

        guard case let .postItMetadataRejected(_, _, _, _, suggestion) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(suggestion == nil)
    }

    @Test("A malformed tint is refused", arguments: ["yellow", "#FF0", "#FFF59D80", "FFF59D"])
    func malformedTintIsRefused(tint: String) throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.tint": .string(tint)], on: "Board/Question", in: makeDocument()
        ))

        guard case let .postItMetadataRejected(_, key, _, accepted, _) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(key == "common.metadata.tint")
        #expect(accepted == ["#RRGGBB"])
    }

    @Test("An author that is not a string is refused")
    func nonStringAuthorIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.author": .int(7)], on: "Board/Question", in: makeDocument()
        ))

        #expect(error.code == "postItMetadataRejected")
    }

    @Test("A whole-object metadata write is checked the same way")
    func wholeObjectWriteIsChecked() throws {
        let error = try refusal(
            setting: ["common.metadata": .dictionary(["type": .string("postit"), "kind": .string("anwser")])],
            on: "Board/Question", in: makeDocument()
        )

        #expect(error?.code == "postItMetadataRejected")
    }

    // MARK: - What passes

    @Test("Valid spellings, a #RRGGBB tint and a cleared key are written")
    func validValuesAreWritten() throws {
        let document = try makeDocument()
        let error = try refusal(
            setting: [
                "common.metadata.kind": .string("answer"),
                "common.metadata.state": .string("resolved"),
                "common.metadata.tint": .string("#a5d6a7"),
                "common.metadata.author": .string("ana"),
                "common.metadata.copiedFrom": .string("claude"),
                "common.metadata.leaf": .null,
            ],
            on: "Board/Question", in: document
        )
        #expect(error == nil)

        let postIt = try #require(document.node(id: "Nte01").flatMap(PenPostIt.Metadata.init))
        #expect(postIt.kind == .valid(.answer))
        #expect(postIt.state == .valid(.resolved))
        #expect(postIt.tint?.value == PenHexColor(red: 0xA5, green: 0xD6, blue: 0xA7))
        #expect(postIt.copiedFrom == "claude")
    }

    @Test("A file holding misspellings still opens, and a write that leaves them untouched passes")
    func legacyValuesPassThrough() throws {
        let document = try makeDocument()
        let error = try refusal(
            setting: ["common.metadata.author": .string("ana")], on: "Board/Legacy", in: document
        )
        #expect(error == nil)

        let postIt = try #require(document.node(id: "Nte02").flatMap(PenPostIt.Metadata.init))
        #expect(postIt.kind == .unrecognized("questoin"))
        #expect(postIt.author == "ana")
    }

    @Test("Metadata that is not a post-it's is not held to the convention")
    func nonPostItIsUnchecked() throws {
        let error = try refusal(
            setting: ["common.metadata.kind": .string("questoin")], on: "Board/Plain", in: makeDocument()
        )

        #expect(error == nil)
    }

    // MARK: - add

    @Test("add refuses a post-it with a misspelled kind")
    func addRefusesMisspelledKind() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Added", "content": "new",
            "metadata": ["type": "postit", "kind": "questoin"],
        ])

        #expect {
            try BatchApplier.applyOne(.add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document)
        } throws: { error in
            (error as? EditingError)?.code == "postItMetadataRejected"
        }
    }

    @Test("add refuses a post-it nested inside the added subtree")
    func addRefusesNestedPostIt() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "frame", "name": "Lane", "layout": "none", "width": 300, "height": 300,
            "children": [[
                "type": "note", "name": "Added", "content": "new",
                "metadata": ["type": "postit", "tint": "#FFF"],
            ]],
        ])

        #expect {
            try BatchApplier.applyOne(.add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document)
        } throws: { error in
            (error as? EditingError)?.code == "postItMetadataRejected"
        }
    }

    // MARK: - replace

    @Test("replace refuses a post-it with a misspelled state, but keeps a legacy one it leaves untouched")
    func replaceChecksAgainstWhatItReplaces() throws {
        let document = try makeDocument()
        let misspelled = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Question", "content": "new",
            "metadata": ["type": "postit", "state": "opne"],
        ])
        #expect {
            try BatchApplier.applyOne(
                .replace(BatchOperation.ReplaceOp(target: #require(NodeAddress("Board/Question")), node: misspelled)),
                to: document
            )
        } throws: { error in
            (error as? EditingError)?.code == "postItMetadataRejected"
        }

        let legacy = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Legacy", "content": "rewritten",
            "metadata": ["type": "postit", "kind": "questoin", "state": "Closed", "tint": "yellow"],
        ])
        _ = try BatchApplier.applyOne(
            .replace(BatchOperation.ReplaceOp(target: #require(NodeAddress("Board/Legacy")), node: legacy)),
            to: document
        )
    }

    @Test("add accepts a well-formed post-it")
    func addAcceptsWellFormedPostIt() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Added", "content": "new",
            "metadata": ["type": "postit", "kind": "reference", "state": "open", "tint": "#FFF59D"],
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document
        )

        #expect(result.created.isEmpty == false)
    }
}
