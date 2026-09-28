//
//  SlotFillTreeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What `tree --expand` shows of a slot an instance filled.
///
/// The children an instance writes into a slot frame exist only inside its
/// `descendants` map, so a walk that reads children from the flat store alone shows
/// the slot empty however much the render draws in it.
@MainActor
struct SlotFillTreeTests {
    // MARK: - Documents

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(
            forResource: base, withExtension: ext, subdirectory: "Fixtures"
        ) else {
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

    private func expanded() throws -> [TreeRow] {
        try TreeView.rows(of: document("slot-fill.pen"), root: "Page0", expandInstances: true)
    }

    // MARK: - The injected children

    @Test("An expanded instance lists the children it injects into a slot")
    func injectedChildrenAreRows() throws {
        let rows = try expanded()
        #expect(rows.map(\.id).contains("Inst0/Note0"))
        #expect(rows.map(\.id).contains("Inst0/Tag00"))
    }

    @Test("The injected children sit under the slot frame, in the order written")
    func injectedChildrenSitUnderTheSlot() throws {
        let rows = try expanded()
        let slot = try row(rows, id: "Inst0/CSlt0")
        let note = try row(rows, id: "Inst0/Note0")
        let tag = try row(rows, id: "Inst0/Tag00")

        #expect(slot.childCount == 2)
        #expect(note.depth == slot.depth + 1)
        #expect(tag.depth == slot.depth + 1)

        let ids = rows.map(\.id)
        let slotIndex = try #require(ids.firstIndex(of: "Inst0/CSlt0"))
        #expect(ids[slotIndex + 1] == "Inst0/Note0")
        #expect(ids[slotIndex + 2] == "Inst0/Tag00")
    }

    @Test("An injected row carries the id-path address and the instance's revision")
    func injectedRowsCarryIDPaths() throws {
        let document = try document("slot-fill.pen")
        let rows = try TreeView.rows(of: document, root: "Page0", expandInstances: true)
        let note = try row(rows, id: "Inst0/Note0")

        #expect(note.address == "Inst0/Note0")
        #expect(note.type == "text")
        #expect(note.name == "Note")
        #expect(note.rev == document.revision(of: "Inst0"))
        #expect(note.rect != nil)
    }

    @Test("An injected ref is a ref row, and expands to the component it names")
    func injectedRefExpands() throws {
        let rows = try expanded()
        let tag = try row(rows, id: "Inst0/Tag00")

        #expect(tag.type == "ref")
        #expect(tag.isInstance)
        #expect(tag.childCount == 1)

        let text = try row(rows, id: "Inst0/Tag00/BTxt0")
        #expect(text.depth == tag.depth + 1)
    }

    @Test("An override inside the injected subtree reaches the row it names")
    func injectedRefCarriesItsOwnOverrides() throws {
        let rows = try TreeView.rows(
            of: document("slot-fill.pen"),
            root: "Page0",
            expandInstances: true,
            properties: ["kind.content"]
        )
        let text = try row(rows, id: "Inst0/Tag00/BTxt0")
        #expect(text.properties?["kind.content"] == .string("live"))
    }

    @Test("An instance that fills nothing shows the slot empty")
    func anUnfilledSlotStaysEmpty() throws {
        let rows = try expanded()
        let slot = try row(rows, id: "Inst1/CSlt0")
        #expect(slot.childCount == 0)
        #expect(slot.isSlot)
        #expect(!rows.contains { $0.id.hasPrefix("Inst1/Note0") })
    }

    @Test("Without --expand an instance is still one row")
    func unexpandedInstanceIsOneRow() throws {
        let rows = try TreeView.rows(of: document("slot-fill.pen"), root: "Page0")
        #expect(rows.map(\.id) == ["Page0", "Inst0", "Inst1", "Hole0"])
    }
}
