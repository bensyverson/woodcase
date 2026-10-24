//
//  SlotDropTargetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Whether a container can take children (``EditableDocument/acceptsChildren(_:)``): an
/// instance's slot is the only target inside an instance, at any depth, and so is a
/// container inside a slot's content (Penumbra spec §13.5 rules 5 and 7).
@MainActor
struct SlotDropTargetTests {
    @Test("An instance's slot frame takes children, filled, default or empty")
    func slotFrames() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.acceptsChildren("Filled/List"))
        #expect(doc.acceptsChildren("Default/List"))
        #expect(doc.acceptsChildren("Emptied/List"))
    }

    @Test("A nested instance's slot takes children, and so does one inside a fill")
    func slotsAtAnyDepth() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.acceptsChildren("PanelInst/PScr/List"))
        #expect(doc.acceptsChildren("HostInst/Body"))
        #expect(doc.acceptsChildren("HostInst/Nest/List"))
    }

    @Test("Nothing else inside an instance takes children")
    func restOfAnInstance() throws {
        let doc = try SlotScreenFixture.document()

        #expect(!doc.acceptsChildren("Filled/Screen"))
        #expect(!doc.acceptsChildren("Filled"))
        #expect(!doc.acceptsChildren("Filled/Row1/ItemA"))
        #expect(!doc.acceptsChildren("HostInst/Nest/Screen"))
        #expect(!doc.acceptsChildren("PanelInst/PScr/Screen"))
    }

    @Test("A frame inside a fill takes children")
    func containerInAFill() throws {
        let json = """
        {"version": "2.19", "children": [
          {"id": "Card", "type": "frame", "reusable": true, "width": 200, "height": 100, "children": [
            {"id": "Body", "name": "Body", "type": "frame", "slot": [], "width": 150, "height": 80}]},
          {"id": "Inst", "type": "ref", "ref": "Card", "descendants": {"Body": {"children": [
            {"id": "Box1", "type": "frame", "width": 50, "height": 50, "children": [
              {"id": "Deep1", "type": "rectangle", "width": 10, "height": 10}]}]}}}
        ]}
        """
        let doc = try EditableDocument(from: PenParser.parse(Data(json.utf8)))

        #expect(doc.acceptsChildren("Inst/Box1"))
        #expect(!doc.acceptsChildren("Inst/Deep1"))
    }

    @Test("The document's own containers and the canvas take children; a leaf does not")
    func documentNodes() throws {
        let doc = try SlotScreenFixture.document()

        #expect(doc.acceptsChildren(nil))
        #expect(doc.acceptsChildren("Board"))
        #expect(doc.acceptsChildren("List"))
        #expect(!doc.acceptsChildren("Loose"))
        #expect(!doc.acceptsChildren("Nowhere"))
    }
}
