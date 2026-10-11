//
//  PostItRunStateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A prompt's Run queues work in the file (notes design rev 2, decision 14): its
/// `woodcase.state` takes `queued`, `running` and `done`, and `woodcase.requestedBy` names
/// who pressed Run. A note's state keeps `open` and `resolved`; each type is held to its own
/// spellings when an agent writes one.
@MainActor
struct PostItRunStateTests {
    private static let board = """
    {
      "version": "2.20",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 1000, "height": 1000, "layout": "none",
          "children": [
            { "id": "Prm01", "name": "Ask", "type": "prompt", "content": "Tighten the copy", "model": "claude-opus-5-5",
              "metadata": { "type": "woodcase", "woodcase": { "state": "queued", "requestedBy": "ben" } } },
            { "id": "Nte01", "name": "Sticky", "type": "note", "content": "hi",
              "metadata": { "type": "woodcase", "woodcase": { "state": "open" } } }
          ]
        }
      ]
    }
    """

    private func makeDocument() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Self.board))
    }

    /// Runs a `set` and returns the refusal it raised, or `nil` when it applied.
    private func refusal(_ key: String, _ value: String, on address: String) throws -> EditingError? {
        let target = try #require(NodeAddress(address))
        do {
            let set = BatchOperation.SetOp(target: target, props: [key: .string(value)])
            _ = try BatchApplier.applyOne(.set(set), to: makeDocument())
            return nil
        } catch let error as EditingError {
            return error
        }
    }

    @Test("A prompt's run states are public and typed, and requestedBy is a note key")
    func runStatesAreTyped() {
        #expect(PenPostIt.RunState.allCases.map(\.rawValue) == ["queued", "running", "done"])
        #expect(PenMetadata.WoodcaseKey.requestedBy.group == .note)
        #expect(PenMetadata.WoodcaseKey.requestedBy.shape == .string)
        #expect(PenMetadata.WoodcaseKey.requestedBy.oldSpelling == nil)
        #expect(PenPostIt.keys.contains(.requestedBy))
    }

    @Test("A prompt reads its state as a run state, and who requested it")
    func promptReadsRunState() throws {
        let document = try makeDocument()
        let prompt = try #require(document.node(id: "Prm01"))
        let metadata = try #require(PenPostIt.Metadata(prompt))
        #expect(metadata.runState == .valid(.queued))
        #expect(metadata.state == nil)
        #expect(metadata.requestedBy == "ben")

        let noteNode = try #require(document.node(id: "Nte01"))
        let note = try #require(PenPostIt.Metadata(noteNode))
        #expect(note.state == .valid(.open))
        #expect(note.runState == nil)
    }

    @Test("A prompt's state is a run state: running is accepted, a misspelling suggests the run state")
    func promptStateIsHeldToRunStates() throws {
        #expect(try refusal("common.metadata.woodcase.state", "running", on: "Board/Ask") == nil)
        let error = try #require(try refusal("common.metadata.woodcase.state", "queud", on: "Board/Ask"))
        guard case let .postItMetadataRejected(_, key, _, accepted, suggestion) = error else {
            Issue.record("refused as \(error)")
            return
        }
        #expect(key == "common.metadata.woodcase.state")
        #expect(accepted == ["queued", "running", "done"])
        #expect(suggestion == "queued")
    }

    @Test("A note's state is not a run state, and a prompt's is not open or resolved")
    func eachTypeKeepsItsStates() throws {
        let onNote = try #require(try refusal("common.metadata.woodcase.state", "queued", on: "Board/Sticky"))
        guard case let .postItMetadataRejected(_, _, _, accepted, _) = onNote else {
            Issue.record("refused as \(onNote)")
            return
        }
        #expect(accepted == ["open", "resolved"])
        #expect(try refusal("common.metadata.woodcase.state", "resolved", on: "Board/Ask") != nil)
    }

    @Test("requestedBy takes a string")
    func requestedByTakesAString() throws {
        #expect(try refusal("common.metadata.woodcase.requestedBy", "claude", on: "Board/Ask") == nil)
    }

    @Test("The state key's shape depends on the node it is written to")
    func stateShapeByKind() {
        let prompt = PenNode.Kind.prompt(PenNode.PromptData())
        let note = PenNode.Kind.note(PenNode.NoteData())
        #expect(PenMetadata.WoodcaseKey.state.shape(on: prompt) == .oneOf(["queued", "running", "done"]))
        #expect(PenMetadata.WoodcaseKey.state.shape(on: note) == .oneOf(["open", "resolved"]))
        #expect(PenMetadata.WoodcaseKey.tint.shape(on: prompt) == .hexColor)
    }
}
