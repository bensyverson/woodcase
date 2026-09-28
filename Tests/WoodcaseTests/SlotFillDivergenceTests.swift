//
//  SlotFillDivergenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a write says about filling a slot, and about an override that adds a property
/// the component leaves unset.
///
/// Both were reported as divergences by a check whose accepted-key list disagreed with
/// ``PenNodePatcher``: a `children` override applies and draws, and adding `enabled` to
/// a descendant is the sanctioned way an instance varies from its component.
@MainActor
struct SlotFillDivergenceTests {
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

    /// One text child, as an instance would write it into a slot.
    private var injectedChildren: AnyCodable {
        .array([.dictionary([
            "id": .string("Wrt01"),
            "name": .string("Written"),
            "type": .string("text"),
            "content": .string("written into the slot"),
            "fontSize": .int(12),
            "fill": .string("#000000"),
            "width": .int(120),
            "height": .int(16),
        ])])
    }

    // MARK: - Filling a slot

    @Test("A children override on a slot frame reports no divergence")
    func fillingASlotIsQuiet() throws {
        let document = try document("slot-fill.pen")
        let slot = try #require(NodeAddress("Inst1/CSlt0"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: slot, props: ["children": injectedChildren])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    @Test("A children override on a childless frame that is not a slot reports no divergence")
    func fillingAPlainFrameIsQuiet() throws {
        let document = try document("slot-fill.pen")
        let footer = try #require(NodeAddress("Inst1/CFtr0"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: footer, props: ["children": injectedChildren])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }

    @Test("A children override applies, and the settled tree renders the injected child")
    func fillingASlotDraws() throws {
        let document = try document("slot-fill.pen")
        let slot = try #require(NodeAddress("Inst1/CSlt0"))

        _ = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: slot, props: ["children": injectedChildren])),
            to: document
        )

        let settled = SettledTree(document: document, theme: [:])
        let injected = try #require(settled.nodes["Inst1/Wrt01"])
        guard case let .text(data) = injected.kind else {
            Issue.record("expected the injected node to be text")
            return
        }
        #expect(data.content == .literal("written into the slot"))
        #expect(settled.rects["Inst1/Wrt01"] != nil)
    }

    @Test("A children override on a node whose type has no children still says nothing reads it")
    func childrenOnALeafIsStillADivergence() throws {
        let document = try document("slot-fill.pen")
        let title = try #require(NodeAddress("Inst1/CTtl0"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: title, props: ["children": injectedChildren])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .unsetOverrideProperty)
        #expect(divergence.severity == .divergence)
        #expect(divergence.note == """
        Page/Empty/Title is a text node and has no children — the override is stored \
        but nothing will read it
        """)
    }

    // MARK: - Adding a property the component leaves unset

    @Test("An override that adds enabled to a descendant is a note, not a divergence")
    func addingEnabledIsANote() throws {
        let document = try document("slot-fill.pen")
        let title = try #require(NodeAddress("Inst0/CTtl0"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: title, props: ["enabled": .bool(false)])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .unsetOverrideProperty)
        #expect(divergence.severity == .note)
        #expect(divergence.note == """
        Page/Filled/Title adds enabled rather than replacing it — Card does not set \
        enabled, which is how an instance varies from its component
        """)
    }

    @Test("A note is marked in the report line; a divergence stands alone")
    func aNoteIsMarkedInTheLine() throws {
        let document = try document("slot-fill.pen")
        let title = try #require(NodeAddress("Inst0/CTtl0"))

        let added = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: title, props: ["opacity": .double(0.5)])),
            to: document
        )
        let note = try #require(added.divergences.first)
        #expect(note.reportLine == "note  \(note.note)")

        let replaced = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: title, props: ["content": .int(3)])),
            to: document
        )
        let divergence = try #require(replaced.divergences.first)
        #expect(divergence.severity == .divergence)
        #expect(divergence.reportLine == divergence.note)
    }

    @Test("An override that replaces a value the component sets stays quiet")
    func replacingASetValueIsQuiet() throws {
        let document = try document("slot-fill.pen")
        let title = try #require(NodeAddress("Inst0/CTtl0"))

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: title, props: ["content": .string("Hi")])),
            to: document
        )

        #expect(result.divergences.isEmpty)
    }
}
