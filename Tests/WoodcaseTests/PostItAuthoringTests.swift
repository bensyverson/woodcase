//
//  PostItAuthoringTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An agent's write to a note's `metadata.woodcase` is held to the convention: a
/// misspelled type or state, a malformed tint or a non-string author is refused with a
/// stable code and the closest spelling, while a file that already holds one still
/// opens and a write that leaves it untouched passes. A write stores only the
/// namespaced key and removes the old spelling of what it writes. See
/// `project/2026-10-04-post-it-design.md`, Convention, as revised by
/// `../Penumbra/project/2026-10-11-notes-comments-and-spans.md`.
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
              "metadata": { "woodcase": { "type": "postit", "state": "open", "author": "claude" } } },
            { "id": "Nte02", "name": "Legacy", "type": "note", "content": "hi",
              "metadata": { "type": "postit", "kind": "questoin", "state": "Closed", "tint": "yellow" } },
            { "id": "Nte03", "name": "Plain", "type": "note", "content": "hi",
              "metadata": { "type": "scratch", "state": "anything" } },
            { "id": "Frm01", "name": "Card", "type": "frame", "width": 10, "height": 10,
              "metadata": { "type": "component", "_role": "card" } }
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

    /// A node's metadata as raw JSON, to see which spelling a write stored.
    private func rawMetadata(_ id: String, in document: EditableDocument) throws -> [String: AnyCodable] {
        let metadata = try #require(document.node(id: id)?.common.metadata)
        return try JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
    }

    // MARK: - Refusals

    @Test("A misspelled state is refused with a stable code and the closest spelling")
    func misspelledStateIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.woodcase.state": .string("reslved")], on: "Board/Question", in: makeDocument()
        ))

        #expect(error.code == "postItMetadataRejected")
        guard case let .postItMetadataRejected(nodeID, key, value, accepted, suggestion) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(nodeID == "Nte01")
        #expect(key == "common.metadata.woodcase.state")
        #expect(value == #""reslved""#)
        #expect(accepted == ["open", "resolved"])
        #expect(suggestion == "resolved")
    }

    @Test("A misspelled type is refused with the closest spelling")
    func misspelledTypeIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.woodcase.type": .string("comemnt")], on: "Board/Question", in: makeDocument()
        ))

        guard case let .postItMetadataRejected(_, key, _, accepted, suggestion) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(key == "common.metadata.woodcase.type")
        #expect(accepted == ["postit", "comment"])
        #expect(suggestion == "comment")
    }

    @Test("A value nowhere near a spelling is refused with no suggestion")
    func farValueHasNoSuggestion() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.woodcase.state": .string("zebra-crossing")], on: "Board/Question", in: makeDocument()
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
            setting: ["common.metadata.woodcase.tint": .string(tint)], on: "Board/Question", in: makeDocument()
        ))

        guard case let .postItMetadataRejected(_, key, _, accepted, _) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(key == "common.metadata.woodcase.tint")
        #expect(accepted == ["#RRGGBB"])
    }

    @Test("An author that is not a string is refused")
    func nonStringAuthorIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.woodcase.author": .int(7)], on: "Board/Question", in: makeDocument()
        ))

        #expect(error.code == "postItMetadataRejected")
    }

    @Test("A font size that is not a number is refused")
    func nonNumericFontSizeIsRefused() throws {
        let error = try #require(try refusal(
            setting: ["common.metadata.woodcase.fontSize": .string("big")], on: "Board/Question", in: makeDocument()
        ))

        guard case let .postItMetadataRejected(_, key, _, accepted, _) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(key == "common.metadata.woodcase.fontSize")
        #expect(accepted == ["a number"])
    }

    @Test("A whole-object metadata write is checked the same way")
    func wholeObjectWriteIsChecked() throws {
        let error = try refusal(
            setting: ["common.metadata": .dictionary(["woodcase": .dictionary(["state": .string("opne")])])],
            on: "Board/Question", in: makeDocument()
        )

        #expect(error?.code == "postItMetadataRejected")
    }

    @Test("An old-style write is held to the convention once it lands in the namespace")
    func oldStyleWriteIsChecked() throws {
        let error = try refusal(
            setting: ["common.metadata.state": .string("opne")], on: "Board/Legacy", in: makeDocument()
        )

        #expect(error?.code == "postItMetadataRejected")
    }

    // MARK: - What passes

    @Test("Valid spellings, a #RRGGBB tint, a text style and a cleared key are written")
    func validValuesAreWritten() throws {
        let document = try makeDocument()
        let error = try refusal(
            setting: [
                "common.metadata.woodcase.type": .string("comment"),
                "common.metadata.woodcase.state": .string("resolved"),
                "common.metadata.woodcase.tint": .string("#a5d6a7"),
                "common.metadata.woodcase.author": .string("ana"),
                "common.metadata.woodcase.copiedFrom": .string("claude"),
                "common.metadata.woodcase.fontSize": .int(20),
                "common.metadata.woodcase.textAlign": .string("center"),
                "common.metadata.woodcase.leaf": .null,
            ],
            on: "Board/Question", in: document
        )
        #expect(error == nil)

        let postIt = try #require(document.node(id: "Nte01").flatMap(PenPostIt.Metadata.init))
        #expect(postIt.type == .valid(.comment))
        #expect(postIt.state == .valid(.resolved))
        #expect(postIt.tint?.value == PenHexColor(red: 0xA5, green: 0xD6, blue: 0xA7))
        #expect(postIt.copiedFrom == "claude")
        #expect(document.node(id: "Nte01")?.common.metadata?[woodcase: .fontSize] == .int(20))
    }

    @Test("A file holding misspellings still opens, and a write that leaves them untouched passes")
    func legacyValuesPassThrough() throws {
        let document = try makeDocument()
        let error = try refusal(
            setting: ["common.metadata.woodcase.author": .string("ana")], on: "Board/Legacy", in: document
        )
        #expect(error == nil)

        let postIt = try #require(document.node(id: "Nte02").flatMap(PenPostIt.Metadata.init))
        #expect(postIt.state == .unrecognized("Closed"))
        #expect(postIt.author == "ana")
    }

    @Test("Bare keys on metadata that is not a post-it's are not held to the convention")
    func nonPostItIsUnchecked() throws {
        let document = try makeDocument()
        let error = try refusal(
            setting: ["common.metadata.state": .string("questoin")], on: "Board/Plain", in: document
        )

        #expect(error == nil)
        #expect(try rawMetadata("Nte03", in: document)["state"] == .string("questoin"))
    }

    // MARK: - Old spellings

    @Test("A namespaced write removes the old spelling of the key it writes, and only that one")
    func namespacedWriteRemovesOldSpelling() throws {
        let document = try makeDocument()
        #expect(try refusal(
            setting: ["common.metadata.woodcase.tint": .string("#FFFFFF")], on: "Board/Legacy", in: document
        ) == nil)

        let raw = try rawMetadata("Nte02", in: document)
        #expect(raw["tint"] == nil)
        #expect(raw["woodcase"] == .dictionary(["tint": .string("#FFFFFF")]))
        #expect(raw["state"] == .string("Closed"))
        #expect(raw["type"] == .string("postit"))
    }

    @Test("An old-style post-it write is stored under the namespace")
    func oldStylePostItWriteMovesIn() throws {
        let document = try makeDocument()
        #expect(try refusal(
            setting: ["common.metadata.state": .string("resolved")], on: "Board/Legacy", in: document
        ) == nil)

        let raw = try rawMetadata("Nte02", in: document)
        #expect(raw["state"] == nil)
        #expect(raw["woodcase"] == .dictionary(["state": .string("resolved")]))
    }

    @Test("An underscore code-gen write is stored under the namespace")
    func underscoreWriteMovesIn() throws {
        let document = try makeDocument()
        #expect(try refusal(
            setting: ["common.metadata._role": .string("button")], on: "Board/Card", in: document
        ) == nil)

        let raw = try rawMetadata("Frm01", in: document)
        #expect(raw == [
            "type": .string("component"),
            "woodcase": .dictionary(["role": .string("button")]),
        ])
    }

    @Test("A legacy kind is neither checked nor moved")
    func legacyKindIsLeftAsWritten() throws {
        let document = try makeDocument()
        #expect(try refusal(
            setting: ["common.metadata.kind": .string("anything")], on: "Board/Legacy", in: document
        ) == nil)

        #expect(try rawMetadata("Nte02", in: document)["kind"] == .string("anything"))
    }

    // MARK: - add

    @Test("add refuses a post-it with a misspelled state")
    func addRefusesMisspelledState() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Added", "content": "new",
            "metadata": ["woodcase": ["state": "opne"]],
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
                "metadata": ["woodcase": ["tint": "#FFF"]],
            ]],
        ])

        #expect {
            try BatchApplier.applyOne(.add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document)
        } throws: { error in
            (error as? EditingError)?.code == "postItMetadataRejected"
        }
    }

    @Test("add stores an old-style post-it under the namespace")
    func addMovesOldStyleKeysIn() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Added", "content": "new",
            "metadata": ["type": "postit", "state": "open", "kind": "question", "author": "ana"],
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document
        )

        let id = try #require(result.created.first?.id)
        #expect(try rawMetadata(id, in: document) == [
            "type": .string("woodcase"),
            "kind": .string("question"),
            "woodcase": .dictionary([
                "type": .string("postit"), "state": .string("open"), "author": .string("ana"),
            ]),
        ])
    }

    @Test("add gives namespaced metadata with no type the type woodcase")
    func addTypesTypelessMetadata() throws {
        let document = try makeDocument()
        let node = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Added", "content": "new",
            "metadata": ["woodcase": ["state": "open"]],
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document
        )

        let id = try #require(result.created.first?.id)
        #expect(try rawMetadata(id, in: document)["type"] == .string("woodcase"))
    }

    @Test("A whole-object metadata write with no type gets the type woodcase")
    func wholeObjectWriteIsTyped() throws {
        let document = try makeDocument()
        #expect(try refusal(
            setting: ["common.metadata": .dictionary(["woodcase": .dictionary(["state": .string("open")])])],
            on: "Board/Question", in: document
        ) == nil)

        #expect(try rawMetadata("Nte01", in: document)["type"] == .string("woodcase"))
    }

    @Test("A write never touches a type someone else wrote")
    func foreignTypeIsKept() throws {
        let document = try makeDocument()
        #expect(try refusal(
            setting: ["common.metadata.woodcase.tint": .string("#FFFFFF")], on: "Board/Plain", in: document
        ) == nil)

        #expect(try rawMetadata("Nte03", in: document)["type"] == .string("scratch"))
    }

    // MARK: - replace

    @Test("replace refuses a post-it with a misspelled state, but keeps a legacy one it leaves untouched")
    func replaceChecksAgainstWhatItReplaces() throws {
        let document = try makeDocument()
        let misspelled = try PenSubtreeDecoder.node(from: [
            "type": "note", "name": "Question", "content": "new",
            "metadata": ["woodcase": ["type": "postit", "state": "opne"]],
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
            "metadata": ["woodcase": ["type": "postit", "state": "open", "tint": "#FFF59D"]],
        ])

        let result = try BatchApplier.applyOne(
            .add(BatchOperation.AddOp(node: node, parent: NodeAddress("Board"))), to: document
        )

        #expect(result.created.isEmpty == false)
    }
}
