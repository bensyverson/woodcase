//
//  TreeViewTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct TreeViewTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    private func document(_ fixture: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: fixtureURL(fixture)))
    }

    private func row(_ rows: [TreeRow], id: String) throws -> TreeRow {
        try #require(rows.first { $0.id == id })
    }

    // MARK: - Rects

    @Test("Rows carry the layout rects the fixture's golden layout pins")
    func rowsMatchGoldenLayout() throws {
        let doc = try document("layout-absolute.pen")
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: fixtureURL("layout-absolute.layout.json"))
        )
        let rows = try TreeView.rows(of: doc)

        #expect(rows.count == expected.count)
        for row in rows {
            #expect(row.rect == expected[row.id], "rect mismatch for \(row.id)")
        }
    }

    @Test("Rows are pre-order, depth-labelled, and report their child count")
    func preOrderWithDepths() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        #expect(rows.map(\.id) == ["Card1", "Fit01", "Ovr01", "Out01"])
        #expect(rows.map(\.depth) == [0, 1, 1, 1])
        #expect(rows.map(\.childCount) == [3, 0, 0, 0])
        #expect(rows.map(\.type) == ["frame", "rectangle", "rectangle", "rectangle"])
    }

    // MARK: - Clipping

    @Test("A child that overruns its parent is flagged partial, one entirely outside is full")
    func overflowIsFlagged() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        #expect(try row(rows, id: "Card1").clip == TreeRow.Clip.none)
        #expect(try row(rows, id: "Fit01").clip == TreeRow.Clip.none)
        #expect(try row(rows, id: "Ovr01").clip == TreeRow.Clip.partial)
        #expect(try row(rows, id: "Out01").clip == TreeRow.Clip.full)
    }

    @Test("A group's children are never flagged: a group has no box to clip them, and its rect is their union")
    func groupChildrenAreNotFlagged() throws {
        // `pos`'s children sit at (20, 30) and (80, 60) from the group's anchor, inside the
        // union at (20, 30) that is the group's box; `neg`'s reach left of and above it.
        let rows = try TreeView.rows(of: document("render-free-groups.pen"))
        for id in ["GposA", "GposB", "GnegA", "GnegB", "GnestHa", "GnestHb"] {
            let child = try row(rows, id: id)
            #expect(child.clip == TreeRow.Clip.none, "\(id) is flagged \(child.clip)")
        }
    }

    @Test("overflowAxes names which edges a clipped row crosses, and is empty otherwise")
    func overflowAxesNameTheCrossedEdges() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        // Fit01 (10,10 50×50) sits entirely inside Card1's 200×100 box.
        #expect(try row(rows, id: "Fit01").overflowAxes.isEmpty)
        // Ovr01 (160,20 80×40) crosses the right edge only: x 160...240 > 200, y 20...60 <= 100.
        #expect(try row(rows, id: "Ovr01").overflowAxes == [.horizontal])
        // Out01 (260,120 20×20) is entirely outside on both axes.
        #expect(try row(rows, id: "Out01").overflowAxes == [.horizontal, .vertical])
    }

    // MARK: - Names and addresses

    @Test("An unnamed node has no name and is addressed by its id marker")
    func unnamedNodesAreMarked() throws {
        let doc = try document("tree-overflow.pen")
        let unnamed = try row(TreeView.rows(of: doc), id: "Out01")
        #expect(unnamed.name == nil)
        #expect(unnamed.address == "Card/#Out01")
        #expect(try doc.resolve(unnamed.address) == .node(id: "Out01"))
    }

    @Test("A named node is addressed by its name path")
    func namedNodesUseNamePaths() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        let card = try row(rows, id: "Card1")
        #expect(card.name == "Card")
        #expect(card.address == "Card")
        #expect(try row(rows, id: "Fit01").address == "Card/fits")
    }

    // MARK: - Instances

    @Test("A ref is one row when instances are not expanded")
    func collapsedRefIsOneRow() throws {
        let rows = try TreeView.rows(of: document("addressing.pen"))
        let nav = try row(rows, id: "Nav01")
        #expect(nav.type == "ref")
        #expect(nav.isInstance)
        #expect(nav.childCount == 2)
        #expect(!rows.contains { $0.id.hasPrefix("Nav01/") })
    }

    @Test("A reusable component definition is flagged and still laid out")
    func reusableDefinitionsAreFlagged() throws {
        let rows = try TreeView.rows(of: document("addressing.pen"))
        let button = try row(rows, id: "Btn01")
        let dashboard = try row(rows, id: "Dash1")
        #expect(button.isReusable)
        #expect(button.rect?.width == 120)
        #expect(!dashboard.isReusable)
    }

    @Test("Every expanded row's address resolves to the target the row names")
    func expandedAddressesResolve() throws {
        let doc = try document("addressing.pen")
        let rows = try TreeView.rows(of: doc, expandInstances: true)

        #expect(rows.contains { $0.id == "Nav01/Lbl01" })
        #expect(rows.contains { $0.id == "Nav01/Bdg01/Cnt01" })
        for row in rows {
            let resolved = try doc.resolve(row.address)
            #expect(resolved.address == row.id, "\(row.address) resolved to \(resolved.address), not \(row.id)")
        }
    }

    @Test("An expanded instance descendant carries the ref's override, not the definition's value")
    func expandedRowsReportSettledProperties() throws {
        let doc = try document("addressing.pen")
        let rows = try TreeView.rows(of: doc, expandInstances: true, properties: ["kind.content"])
        let label = try row(rows, id: "Nav01/Lbl01")
        let count = try row(rows, id: "Nav01/Bdg01/Cnt01")
        #expect(label.properties?["kind.content"] == .string("Menu"))
        #expect(count.properties?["kind.content"] == .string("3"))
    }

    // MARK: - Slots

    @Test("A frame with a slot is flagged; a plain frame is not")
    func slotFramesAreFlagged() throws {
        let rows = try TreeView.rows(of: document("tree-slot.pen"))
        #expect(try row(rows, id: "Fld01").isSlot)
        #expect(try !(row(rows, id: "Ord01").isSlot))
    }

    // MARK: - Scoping

    @Test("A root address scopes the walk to that subtree")
    func rootScopesTheWalk() throws {
        let rows = try TreeView.rows(of: document("addressing.pen"), root: "Dashboard/Header")
        #expect(rows.map(\.id) == ["Hdr01", "Ttl01", "Unn01", "Slsh1"])
        #expect(rows[0].depth == 0)
    }

    @Test("A root that names nothing is an error, not an empty answer")
    func unknownRootThrows() throws {
        let doc = try document("addressing.pen")
        #expect(throws: EditingError.self) {
            try TreeView.rows(of: doc, root: "Nope")
        }
    }

    @Test("A depth limit stops descent but the last row still reports its children")
    func depthLimitStopsDescent() throws {
        let rows = try TreeView.rows(of: document("addressing.pen"), root: "Dashboard", depth: 1)
        #expect(rows.map(\.id) == ["Dash1", "Hdr01", "Body1"])
        #expect(try row(rows, id: "Hdr01").childCount == 3)
        #expect(try row(rows, id: "Body1").childCount == 2)
    }

    // MARK: - Property columns

    @Test("Requested property columns are read from the settled document")
    func propertyColumns() throws {
        let rows = try TreeView.rows(
            of: document("tree-overflow.pen"),
            properties: ["kind.fills", "common.name"]
        )
        let card = try row(rows, id: "Card1")
        #expect(card.properties?["common.name"] == .string("Card"))
        #expect(card.properties?["kind.fills"] != nil)
    }

    @Test("A property that is not part of a node's kind is absent from that row")
    func propertyNotOnKindIsOmitted() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"), properties: ["kind.content"])
        let card = try row(rows, id: "Card1")
        #expect(card.properties?["kind.content"] == nil)
    }

    @Test("No requested properties means no properties dictionary at all")
    func noPropertiesRequested() throws {
        let rows = try TreeView.rows(of: document("tree-overflow.pen"))
        #expect(rows.allSatisfy { $0.properties == nil })
    }

    // MARK: - Themes

    @Test("Pinning a theme axis that drives a size variable changes the rect")
    func themeChangesRect() throws {
        let doc = try document("parser-themed-variables.pen")
        let compact = try TreeView.rows(of: doc, theme: ["density": "compact"])
        let regular = try TreeView.rows(of: doc, theme: ["density": "regular"])

        let compactLabel = try #require(compact.first { $0.id == "label" }?.rect)
        let regularLabel = try #require(regular.first { $0.id == "label" }?.rect)
        #expect(regularLabel.height > compactLabel.height)
    }

    @Test("An unthemed read still resolves and lays out")
    func defaultThemeResolves() throws {
        let rows = try TreeView.rows(of: document("parser-themed-variables.pen"))
        #expect(rows.map(\.id) == ["container", "label"])
        #expect(rows[0].rect == PenRect(x: 0, y: 0, width: 400, height: 200))
    }

    // MARK: - Revisions

    @Test("Every row carries the node's own revision")
    func rowsCarryTheNodeRevision() throws {
        let doc = try document("addressing.pen")
        let rows = try TreeView.rows(of: doc)

        #expect(!rows.isEmpty)
        for row in rows {
            #expect(row.rev == doc.revision(of: row.id), "rev mismatch for \(row.id)")
        }
    }

    @Test("An expanded instance descendant carries the instance's revision, which is what a write to it quotes")
    func expandedRowsCarryTheInstanceRevision() throws {
        let doc = try document("addressing.pen")
        let rows = try TreeView.rows(of: doc, expandInstances: true)
        let nav = try #require(doc.revision(of: "Nav01"))

        #expect(try row(rows, id: "Nav01/Lbl01").rev == nav)
        #expect(try row(rows, id: "Nav01/Bdg01/Cnt01").rev == nav)
        // The definition's own rows still carry the definition's revisions.
        #expect(try row(rows, id: "Lbl01").rev == doc.revision(of: "Lbl01"))
    }

    @Test("A row's rev covers its whole subtree: an edit deep inside moves every ancestor's row")
    func rowRevCoversTheSubtree() throws {
        let doc = try document("addressing.pen")
        let before = try TreeView.rows(of: doc).reduce(into: [String: String]()) { $0[$1.id] = $1.rev }

        try doc.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Ttl01", properties: ["kind.content": .string("Edited")]
        )))
        let after = try TreeView.rows(of: doc).reduce(into: [String: String]()) { $0[$1.id] = $1.rev }

        let spine: Set = ["Ttl01", "Hdr01", "Dash1"]
        for id in before.keys.sorted() {
            if spine.contains(id) {
                #expect(after[id] != before[id], "\(id) is on the spine and should have moved")
            } else {
                #expect(after[id] == before[id], "\(id) is off the spine and should not have moved")
            }
        }
    }
}
