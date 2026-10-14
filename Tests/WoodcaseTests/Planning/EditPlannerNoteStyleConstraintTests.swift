//
//  EditPlannerNoteStyleConstraintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A note's type size and line height live in `metadata.woodcase` because Pen strips
/// them from the node, and a write there is held to the same range as `kind.fontSize`
/// and `kind.lineHeight` — so an inspector cannot store a 0 pt or negative type size on
/// a note that it would refuse on a text (leaf Af2Qeg).
@MainActor
struct EditPlannerNoteStyleConstraintTests {
    private static let board = """
    {
      "version": "2.20",
      "children": [
        {
          "id": "Brd01", "name": "Board", "type": "frame", "x": 0, "y": 0,
          "width": 1000, "height": 1000, "layout": "none",
          "children": [
            { "id": "Nte01", "name": "Question", "type": "note", "content": "hi",
              "metadata": { "type": "woodcase", "woodcase": { "type": "postit" } } },
            { "id": "Nte02", "name": "Broken", "type": "note", "content": "hi",
              "metadata": { "type": "woodcase", "woodcase": { "type": "postit", "fontSize": 0 } } }
          ]
        }
      ]
    }
    """

    private func refusal(_ intent: EditIntent, at raw: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: raw, in: EditableDocument(from: PenParser.parse(Self.board)))
    }

    private static func constraint(of field: String) throws -> PenValueConstraint {
        try #require(NodePropertyCodec.shape(of: field)?.constraint)
    }

    @Test("A note's metadata type size of 0 or below is refused as kind.fontSize would be")
    func fontSizeOutOfRange() throws {
        for size: AnyCodable in [0, -4, 0.0] {
            let refusal = try #require(try refusal(
                .set(["common.metadata.woodcase.fontSize": size]), at: "Board/Question"
            ))
            #expect(refusal.code == .outOfRange)
            #expect(refusal.property == "common.metadata.woodcase.fontSize")
            #expect(try refusal.expected == Self.constraint(of: "fontSize").summary)
        }
    }

    @Test("A note's metadata line height of 0, or one written in points, is refused as kind.lineHeight would be")
    func lineHeightOutOfRange() throws {
        for height: AnyCodable in [0, -1, 24] {
            let refusal = try #require(try refusal(
                .set(["common.metadata.woodcase.lineHeight": height]), at: "Board/Question"
            ))
            #expect(refusal.code == .outOfRange)
            #expect(refusal.property == "common.metadata.woodcase.lineHeight")
            #expect(refusal.expected?.contains("multiple of fontSize") == true)
        }
    }

    @Test("A whole metadata object carrying a bad type size is refused the same way")
    func wholeObjectWrite() throws {
        let refusal = try #require(try refusal(
            .set(["common.metadata": ["type": "woodcase", "woodcase": ["type": "postit", "fontSize": -2]]]),
            at: "Board/Question"
        ))
        #expect(refusal.code == .outOfRange)
        #expect(refusal.property == "common.metadata.woodcase.fontSize")
    }

    @Test("A type size and line height inside their ranges plan")
    func inRange() throws {
        #expect(try refusal(
            .set(["common.metadata.woodcase.fontSize": 15, "common.metadata.woodcase.lineHeight": 1.4]),
            at: "Board/Question"
        ) == nil)
        #expect(try refusal(.set(["common.metadata.woodcase.fontSize": nil]), at: "Board/Question") == nil)
    }

    @Test("A note whose file already holds a bad type size can be edited around it")
    func unchangedValuePasses() throws {
        #expect(try refusal(.set(["common.metadata.woodcase.tint": "#A5D6A7"]), at: "Board/Broken") == nil)
    }

    @Test("The note keys carry the constraint of the kind key they stand in for")
    func keysShareTheKindConstraint() throws {
        #expect(try PenMetadata.WoodcaseKey.fontSize.constraint == Self.constraint(of: "fontSize"))
        #expect(try PenMetadata.WoodcaseKey.lineHeight.constraint == Self.constraint(of: "lineHeight"))
        #expect(try PenMetadata.WoodcaseKey.letterSpacing.constraint == Self.constraint(of: "letterSpacing"))
        #expect(PenMetadata.WoodcaseKey.tint.constraint == nil)
    }

    @Test("An added note carrying a bad type size is refused with the range it takes")
    func addIsChecked() throws {
        let document = try EditableDocument(from: PenParser.parse(Self.board))
        let note = try PenSubtreeDecoder.node(from: [
            "id": "Nte09", "type": "note", "name": "New", "content": "hi",
            "metadata": ["type": "woodcase", "woodcase": ["fontSize": 0]],
        ])
        let parent = try #require(NodeAddress("Board"))
        do {
            _ = try BatchApplier.applyOne(.add(BatchOperation.AddOp(node: note, parent: parent)), to: document)
            Issue.record("the add was applied")
        } catch let EditingError.postItMetadataRejected(_, key, _, accepted, _) {
            #expect(key == "common.metadata.woodcase.fontSize")
            #expect(try accepted == [Self.constraint(of: "fontSize").summary])
        }
    }
}
