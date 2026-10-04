//
//  DocumentChangesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What the two-way change walk detects, one kind of change at a time.
@MainActor
struct DocumentChangesTests {
    // MARK: - Helpers

    /// Parses a document whose root holds `children`, with optional root members.
    private func document(_ children: String, root: String = "") throws -> EditableDocument {
        let members = root.isEmpty ? "" : "\(root),"
        return try EditableDocument(from: PenParser.parse(#"{"version":"2.20",\#(members)"children":[\#(children)]}"#))
    }

    /// The base tree most tests edit: a page of two rectangles and an empty box, beside a side frame.
    private func tree(
        r1: String = #""width":10,"height":10"#,
        page: String = #"{"type":"rectangle","id":"r1",R1},{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box","children":[]}"#,
        side: String = ""
    ) -> String {
        let pageChildren = page.replacingOccurrences(of: "R1", with: r1)
        let sideChildren = side.isEmpty ? "" : #","children":[\#(side)]"#
        return #"{"type":"frame","id":"page","children":[\#(pageChildren)]},{"type":"frame","id":"side"\#(sideChildren)}"#
    }

    private func changes(_ from: String, _ to: String, fromRoot: String = "", toRoot: String = "") throws -> DocumentChanges {
        try DocumentChanges(from: document(from, root: fromRoot), to: document(to, root: toRoot))
    }

    // MARK: - Nothing changed

    @Test("Identical documents produce no changes")
    func identical() throws {
        let result = try changes(tree(), tree())
        #expect(result.isEmpty)
        #expect(result.nodes.isEmpty)
        #expect(result.document.isEmpty)
    }

    // MARK: - Existence

    @Test("A node only the target holds is added, and its parent's child list changed")
    func added() throws {
        let page = #"{"type":"rectangle","id":"r1",R1},{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box","children":[]},{"type":"ellipse","id":"e1"}"#
        let result = try changes(tree(), tree(page: page))
        let added = try #require(result.nodes["e1"])
        #expect(added.existence == .added)
        #expect(added.from == nil)
        #expect(added.to?.parentID == "page")
        #expect(result.nodes["page"]?.keys == [.children])
        #expect(Set(result.nodes.keys) == ["e1", "page"])
    }

    @Test("A node only the source holds is removed, with its whole subtree")
    func removed() throws {
        let from = tree(side: #"{"type":"frame","id":"inner","children":[{"type":"text","id":"t1","content":"Hi"}]}"#)
        let result = try changes(from, tree())
        #expect(result.nodes["inner"]?.existence == .removed)
        #expect(result.nodes["t1"]?.existence == .removed)
        #expect(result.nodes["t1"]?.from?.parentID == "inner")
        #expect(result.nodes["inner"]?.to == nil)
        #expect(result.nodes["side"]?.keys == [.children, .declaredChildren])
    }

    // MARK: - Placement

    @Test("A move to another parent records the parent on the node and the list on both parents")
    func reparent() throws {
        let page = #"{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box","children":[{"type":"rectangle","id":"r1",R1}]}"#
        let result = try changes(tree(), tree(page: page))
        #expect(result.nodes["r1"]?.keys == [.parent])
        #expect(result.nodes["r1"]?.existence == .kept)
        #expect(result.nodes["r1"]?.from?.parentID == "page")
        #expect(result.nodes["r1"]?.to?.parentID == "box")
        #expect(result.nodes["page"]?.keys == [.children])
        #expect(result.nodes["box"]?.keys == [.children])
        #expect(result.nodes["r2"] == nil)
    }

    @Test("A reorder records the parent's child list and nothing on the siblings")
    func reorder() throws {
        let page = #"{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"rectangle","id":"r1",R1},{"type":"frame","id":"box","children":[]}"#
        let result = try changes(tree(), tree(page: page))
        #expect(Set(result.nodes.keys) == ["page"])
        #expect(result.nodes["page"]?.keys == [.children])
        #expect(result.nodes["page"]?.from?.children == ["r1", "r2", "box"])
        #expect(result.nodes["page"]?.to?.children == ["r2", "r1", "box"])
    }

    @Test("A new container adopting an existing node walks into it and finds the move")
    func adoptedByNewContainer() throws {
        let from = tree()
        let to = tree(side: #"{"type":"frame","id":"wrap","children":[{"type":"rectangle","id":"r2","width":10,"height":10}]}"#)
            .replacingOccurrences(of: #"{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box""#, with: #"{"type":"frame","id":"box""#)
        let result = try changes(from, to)
        #expect(result.nodes["wrap"]?.existence == .added)
        #expect(result.nodes["r2"]?.keys == [.parent])
        #expect(result.nodes["r2"]?.to?.parentID == "wrap")
    }

    @Test("A removed container whose child moved out reports the move, not a removal")
    func childEscapesRemovedContainer() throws {
        let from = tree()
        let to = #"{"type":"frame","id":"side","children":[{"type":"rectangle","id":"r1","width":10,"height":10}]}"#
        let result = try changes(from, to)
        #expect(result.nodes["page"]?.existence == .removed)
        #expect(result.nodes["r2"]?.existence == .removed)
        #expect(result.nodes["box"]?.existence == .removed)
        #expect(result.nodes["r1"]?.keys == [.parent])
        #expect(result.nodes["r1"]?.from?.parentID == "page")
        #expect(result.nodes["r1"]?.to?.parentID == "side")
        #expect(result.document == [.rootOrder])
    }

    @Test("A node promoted to a root changes parent to nil")
    func promotedToRoot() throws {
        let page = #"{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box","children":[]}"#
        let to = tree(page: page) + #",{"type":"rectangle","id":"r1","width":10,"height":10}"#
        let result = try changes(tree(), to)
        #expect(result.nodes["r1"]?.keys == [.parent])
        #expect(result.nodes["r1"]?.to?.parentID == nil)
        #expect(result.nodes["r1"]?.from?.parentID == "page")
        #expect(result.document == [.rootOrder])
    }

    // MARK: - Own content

    @Test("A property edit records its codec path, with both values reachable")
    func property() throws {
        let result = try changes(tree(), tree(r1: #""width":20,"height":10,"name":"Wide""#))
        let change = try #require(result.nodes["r1"])
        #expect(change.keys == [.property("kind.width"), .property("common.name")])
        #expect(change.from?.node.common.name == nil)
        #expect(change.to?.node.common.name == "Wide")
        #expect(Set(result.nodes.keys) == ["r1"])
    }

    @Test("A type change is one key, not every kind key of both types")
    func typeChange() throws {
        let page = #"{"type":"ellipse","id":"r1","width":10,"height":10},{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box","children":[]}"#
        let result = try changes(tree(), tree(page: page))
        #expect(result.nodes["r1"]?.keys == [.type])
    }

    @Test("A type change keeps the common keys it carries")
    func typeChangeWithCommon() throws {
        let page = #"{"type":"ellipse","id":"r1","name":"Dot"},{"type":"rectangle","id":"r2","width":10,"height":10},{"type":"frame","id":"box","children":[]}"#
        let result = try changes(tree(), tree(page: page))
        #expect(result.nodes["r1"]?.keys == [.type, .property("common.name")])
    }

    @Test("A node extra is recorded per key")
    func extras() throws {
        let result = try changes(
            tree(r1: #""width":10,"height":10,"keep":1,"drop":2"#),
            tree(r1: #""width":10,"height":10,"keep":1,"added":3"#)
        )
        #expect(result.nodes["r1"]?.keys == [.extra("drop"), .extra("added")])
        #expect(result.nodes["r1"]?.to?.node.extras["added"] == .int(3))
    }

    @Test("Declared `children: []` against absent children is found by the pruned walk alone")
    func declaredChildren() throws {
        let from = try document(tree())
        let to = try document(tree().replacingOccurrences(of: #"{"type":"frame","id":"box","children":[]}"#, with: #"{"type":"frame","id":"box"}"#))
        #expect(from.revision(of: "page") != to.revision(of: "page"))
        var walk = ChangeWalk(from: from, to: to)
        let result = walk.run()
        // page and side, then page's three children: the walk descends to box along its spine.
        #expect(walk.visits == 5)
        #expect(result.nodes["box"]?.keys == [.declaredChildren])
        #expect(result.nodes["box"]?.from?.children == [])
        #expect(result.nodes["box"]?.to?.children == nil)
        #expect(Set(result.nodes.keys) == ["box"])
    }

    @Test("An instance whose component changed is walked but carries no change of its own")
    func instanceOfChangedComponent() throws {
        let component = { (label: String) in
            #"{"type":"frame","id":"comp","reusable":true,"children":[{"type":"text","id":"label","content":"\#(label)"}]},{"type":"ref","id":"inst","ref":"comp"}"#
        }
        let result = try changes(component("A"), component("B"))
        #expect(Set(result.nodes.keys) == ["label"])
        #expect(result.nodes["label"]?.keys == [.property("kind.content")])
    }

    // MARK: - Document keys

    @Test("Document keys: variables, imports, theme axes, fonts, version, fileToken, root extras, root order")
    func documentKeys() throws {
        let fromRoot = #"""
        "variables":{"keep":{"type":"string","value":"a"},"edit":{"type":"string","value":"a"},"drop":{"type":"string","value":"a"}},
        "imports":{"same":"a.pen","moved":"b.pen","gone":"c.pen"},
        "themes":{"mode":["light","dark"],"size":["s"]},
        "fonts":[{"name":"A","url":"a.ttf"}],
        "fileToken":"t1","stable":1,"vanishes":2
        """#
        let toRoot = #"""
        "variables":{"keep":{"type":"string","value":"a"},"edit":{"type":"string","value":"b"},"new":{"type":"string","value":"a"}},
        "imports":{"same":"a.pen","moved":"bb.pen","fresh":"d.pen"},
        "themes":{"mode":["light","dark","dim"],"size":["s"],"density":["x"]},
        "fonts":[{"name":"B","url":"b.ttf"}],
        "fileToken":"t2","stable":1,"appears":3
        """#
        let reversed = #"{"type":"frame","id":"side"},{"type":"frame","id":"page","children":[]}"#
        let original = #"{"type":"frame","id":"page","children":[]},{"type":"frame","id":"side"}"#
        let result = try changes(original, reversed, fromRoot: fromRoot, toRoot: toRoot)
        #expect(result.document == [
            .variable("edit"), .variable("drop"), .variable("new"),
            .importAlias("moved"), .importAlias("gone"), .importAlias("fresh"),
            .themeAxis("mode"), .themeAxis("density"),
            .fonts, .fileToken, .extra("vanishes"), .extra("appears"), .rootOrder,
        ])
        #expect(result.nodes.isEmpty)
    }

    @Test("An empty table declared on one side only is a document key, like an empty child list")
    func declaredTables() throws {
        let declared = #""variables":{},"imports":{},"themes":{}"#
        let result = try changes(tree(), tree(), fromRoot: declared)
        #expect(result.document == [.declaredTable(.variables), .declaredTable(.imports), .declaredTable(.themes)])
    }

    @Test("A version change is a document key")
    func version() throws {
        let from = try document(tree())
        let to = try document(tree())
        to.version = "2.99"
        #expect(DocumentChanges(from: from, to: to).document == [.version])
    }
}
