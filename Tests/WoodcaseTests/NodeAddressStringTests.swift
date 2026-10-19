//
//  NodeAddressStringTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditableDocument/address(of:)``: a node's name path with an id marker wherever a name
/// alone would be ambiguous, so it always resolves back to the node it names — the string
/// an editor copies for `woodcase get`.
@MainActor
struct NodeAddressStringTests {
    // MARK: - Fixture

    /// `Page` holds `Board`, whose children are two texts named `Title` (`r1`, `r2`), an
    /// unnamed rectangle, a text named `a/b`, one named `#tag`, a text whose name is another
    /// node's id (`r2`), a uniquely named `Caption`, and two instances of `Button` both named
    /// `Chip`. `Button` holds two texts named `Label` and a frame `Inner` holding an
    /// instance of `Icon`, whose one child is `Dot`. `Shell` and `Holder/Shell` both have a
    /// child named `Item`, so the name path `Shell/Item` matches two nodes.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Page", "name": "Page", "x": 0, "y": 0, "width": 800, "height": 600,
          "layout": "none", "children": [
          { "type": "frame", "id": "Board", "name": "Board", "x": 0, "y": 0, "width": 400, "height": 300,
            "layout": "none", "children": [
            { "type": "text", "id": "r1", "name": "Title", "content": "A" },
            { "type": "text", "id": "r2", "name": "Title", "content": "B" },
            { "type": "rectangle", "id": "anon", "x": 0, "y": 0, "width": 10, "height": 10 },
            { "type": "text", "id": "sl", "name": "a/b", "content": "C" },
            { "type": "text", "id": "hs", "name": "#tag", "content": "D" },
            { "type": "text", "id": "imp", "name": "r2", "content": "E" },
            { "type": "text", "id": "cap", "name": "Caption", "content": "F" },
            { "type": "ref", "id": "Inst", "name": "Chip", "ref": "Btn", "x": 0, "y": 100 },
            { "type": "ref", "id": "Inst2", "name": "Chip", "ref": "Btn", "x": 0, "y": 200 }
          ] }
        ] },
        { "type": "frame", "id": "Btn", "name": "Button", "reusable": true, "x": 0, "y": 1000,
          "width": 120, "height": 40, "layout": "none", "children": [
          { "type": "text", "id": "Lbl", "name": "Label", "content": "Go" },
          { "type": "text", "id": "Lbl2", "name": "Label", "content": "Stop" },
          { "type": "frame", "id": "Grp", "name": "Inner", "width": 20, "height": 20, "layout": "none",
            "children": [
            { "type": "ref", "id": "Ico", "name": "Icon", "ref": "IconC" }
          ] }
        ] },
        { "type": "frame", "id": "IconC", "name": "Glyph", "reusable": true, "x": 0, "y": 1100,
          "width": 10, "height": 10, "layout": "none", "children": [
          { "type": "rectangle", "id": "Dot", "name": "Dot", "width": 4, "height": 4 }
        ] },
        { "type": "frame", "id": "S1", "name": "Shell", "x": 1000, "y": 0, "width": 10, "height": 10,
          "layout": "none", "children": [
          { "type": "rectangle", "id": "i1", "name": "Item", "width": 4, "height": 4 }
        ] },
        { "type": "frame", "id": "H", "name": "Holder", "x": 1100, "y": 0, "width": 10, "height": 10,
          "layout": "none", "children": [
          { "type": "frame", "id": "S2", "name": "Shell", "width": 10, "height": 10, "layout": "none",
            "children": [
            { "type": "rectangle", "id": "i2", "name": "Item", "width": 4, "height": 4 }
          ] }
        ] }
      ]
    }
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(Self.json.utf8)))
    }

    private func fixture(_ name: String) throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - Plain nodes

    @Test("A node no sibling shares a name with prints its plain name path")
    func uniqueNamesStayNames() throws {
        let doc = try document()
        #expect(doc.address(of: .node(id: "cap")) == "Page/Board/Caption")
        #expect(doc.address(of: .node(id: "Board")) == "Page/Board")
    }

    @Test("Two siblings named Title are told apart by id, and each resolves back")
    func duplicateSiblings() throws {
        let doc = try document()
        let first = doc.address(of: .node(id: "r1"))
        let second = doc.address(of: .node(id: "r2"))
        #expect(first == "Page/Board/#r1")
        #expect(second == "Page/Board/#r2")
        #expect(try doc.resolve(first) == .node(id: "r1"))
        #expect(try doc.resolve(second) == .node(id: "r2"))
    }

    @Test("An unnamed node, and names holding / or starting with #, use the id marker")
    func unreadableNames() throws {
        let doc = try document()
        #expect(doc.address(of: .node(id: "anon")) == "Page/Board/#anon")
        #expect(doc.address(of: .node(id: "sl")) == "Page/Board/#sl")
        #expect(doc.address(of: .node(id: "hs")) == "Page/Board/#hs")
        for id in ["anon", "sl", "hs"] {
            #expect(try doc.resolve(doc.address(of: .node(id: id))) == .node(id: id))
        }
    }

    @Test("A name that is a sibling's id is written as an id, since an id beats a name")
    func nameShadowedByAnID() throws {
        let doc = try document()
        let address = doc.address(of: .node(id: "imp"))
        #expect(address == "Page/Board/#imp")
        #expect(try doc.resolve(address) == .node(id: "imp"))
    }

    @Test("A path whose first segment names several nodes anchors its root by id")
    func ambiguousPrefix() throws {
        let doc = try document()
        #expect(doc.address(of: .node(id: "i1")) == "#S1/Item")
        #expect(doc.address(of: .node(id: "i2")) == "Holder/Shell/Item")
        #expect(try doc.resolve(doc.address(of: .node(id: "i1"))) == .node(id: "i1"))
    }

    // MARK: - Instances

    @Test("A node inside one of two same-named instances names that instance by id")
    func instanceDescendants() throws {
        let doc = try document()
        let label = ResolvedNodeAddress.instanceDescendant(refID: "Inst", descendantKey: "Lbl")
        #expect(doc.address(of: label) == "Page/Board/#Inst/#Lbl")
        #expect(try doc.resolve(doc.address(of: label)) == label)

        let dot = ResolvedNodeAddress.instanceDescendant(refID: "Inst2", descendantKey: "Ico/Dot")
        #expect(doc.address(of: dot) == "Page/Board/#Inst2/Inner/Icon/Dot")
        #expect(try doc.resolve(doc.address(of: dot)) == dot)
    }

    // MARK: - Every node round-trips

    @Test("Every node and instance descendant's address resolves back to it")
    func everyRowRoundTrips() throws {
        let doc = try document()
        try expectEveryRowRoundTrips(in: doc)
    }

    @Test(
        "Every row of the addressing fixtures round-trips",
        arguments: ["addressing.pen", "addressing-nested-instance.pen", "addressing-ref-chain.pen", "slot-fill.pen"]
    )
    func fixturesRoundTrip(name: String) throws {
        try expectEveryRowRoundTrips(in: fixture(name))
    }

    private func expectEveryRowRoundTrips(in doc: EditableDocument) throws {
        let rows = try TreeView.rows(of: doc, expandInstances: true)
        #expect(!rows.isEmpty)
        for row in rows {
            let resolved = try doc.resolve(row.id)
            let address = doc.address(of: resolved)
            #expect(try doc.resolve(address) == resolved, "\(address) does not resolve back to \(row.id)")
        }
    }
}
