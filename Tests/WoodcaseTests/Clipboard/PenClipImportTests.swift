//
//  PenClipImportTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/extract(nodeIDs:from:)`` brings a component from an imported library along
/// as a local definition, with the library variables it uses, so the clip needs no
/// library to draw.
struct PenClipImportTests {
    /// `Fixtures/imports/app.pen`, read with `kit.lib.pen` as its library.
    private func document() throws -> EditableDocument {
        try EditableDocumentLibrariesTests.document().0
    }

    @Test("An instance of a library component carries it, and what it uses, as local definitions")
    func libraryComponentBecomesLocal() throws {
        let clip = try PenClip.extract(nodeIDs: ["Ins02"], from: document())

        #expect(clip.contentIDs == ["Ins02"])
        #expect(Set(clip.document.children.map(\.id)) == ["Ins02", "K:Card1", "K:Chip1"])
        #expect(clip.document.variables?.keys.sorted() == ["K:accent"])
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("The clip draws the library instance with no library attached")
    func clipDrawsWithoutLibrary() throws {
        let clip = try PenClip.extract(nodeIDs: ["Ins02"], from: document())

        let expanded = EditableDocument(from: clip.document).expanded(for: .canvas)
        let index = PenClipFixture.index(expanded.children)
        guard case let .text(label)? = index["Ins02/K:Cc001/K:Txt01"]?.kind else {
            Issue.record("the nested library label did not expand")
            return
        }
        #expect(label.content == .literal("Nested"))
    }

    @Test("A local component that uses a library one carries both")
    func localComponentUsingLibrary() throws {
        let clip = try PenClip.extract(nodeIDs: ["Ins03"], from: document())

        #expect(clip.document.children.map(\.id) == ["Ins03", "Wrap1", "K:Chip1"])
    }
}
