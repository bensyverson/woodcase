//
//  EditableDocumentBoardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditableDocument/board(at:)``: the top-most top-level frame under a canvas point, as a
/// click there finds it.
struct EditableDocumentBoardTests {
    private func document() throws -> EditableDocument {
        try PasteFixture.document("""
        { "version": "2.17", "children": [
          { "id": "Under", "type": "frame", "x": 0, "y": 0, "width": 100, "height": 100, "layout": "none" },
          { "id": "Over", "type": "frame", "x": 50, "y": 50, "width": 100, "height": 100, "layout": "none" },
          { "id": "Shape", "type": "rectangle", "x": 0, "y": 0, "width": 40, "height": 40 },
          { "id": "Comp", "type": "frame", "reusable": true, "x": 500, "y": 0, "width": 10, "height": 10 }
        ] }
        """)
    }

    @Test("Where boards overlap, the top-most wins")
    func topMost() throws {
        #expect(try document().board(at: PenPoint(x: 75, y: 75)) == "Over")
        #expect(try document().board(at: PenPoint(x: 25, y: 75)) == "Under")
    }

    @Test("A top-level shape is not a board, so the board beneath it is found")
    func shapeIsNotABoard() throws {
        #expect(try document().board(at: PenPoint(x: 10, y: 10)) == "Under")
    }

    @Test("A component's own frame is a board")
    func componentIsABoard() throws {
        #expect(try document().board(at: PenPoint(x: 505, y: 5)) == "Comp")
    }

    @Test("Over empty canvas, or on a board's far edge, there is none")
    func none() throws {
        #expect(try document().board(at: PenPoint(x: 300, y: 300)) == nil)
        #expect(try document().board(at: PenPoint(x: 510, y: 5)) == nil)
    }
}
