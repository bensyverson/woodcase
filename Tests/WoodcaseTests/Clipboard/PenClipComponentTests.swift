//
//  PenClipComponentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/extract(nodeIDs:from:)`` carries every component the copy draws: the one an
/// instance names, the ones that component uses, the far end of a ref chain — and never
/// a definition twice.
struct PenClipComponentTests {
    @Test("An instance carries its component and the components that component uses")
    func instanceCarriesNestedComponents() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: document)

        #expect(clip.contentIDs == ["BtnI"])
        #expect(clip.document.children.map(\.id) == ["BtnI", "Icon", "Btn"])
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("The instance stays an instance, and its definitions are copied as stored")
    func definitionsAreCanonical() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: document)

        let roots = Dictionary(uniqueKeysWithValues: clip.document.children.map { ($0.id, $0) })
        guard case let .ref(data)? = roots["BtnI"]?.kind else {
            Issue.record("the copied instance is not a ref")
            return
        }
        #expect(data.ref == "Btn")
        #expect(try roots["Btn"] == (document.materializeSubtree(rootID: "Btn")))
        #expect(try roots["Icon"] == (document.materializeSubtree(rootID: "Icon")))
    }

    @Test("A ref chain carries every component along it")
    func refChainCarriesEveryLink() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["AliasI"], from: document)

        #expect(clip.document.children.map(\.id) == ["AliasI", "Icon", "Btn", "Alias"])
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("A component defined inside another travels inside it, not beside it")
    func nestedDefinitionIsNotDuplicated() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["OuterI"], from: document)

        #expect(clip.document.children.map(\.id) == ["OuterI", "Outer"])
        #expect(PenClipFixture.allIDs(in: clip.document.children).contains("Inner"))
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("A copied component the copy also uses is carried once, as the copy")
    func selectedComponentIsNotRepeated() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Icon", "BtnI"], from: document)

        #expect(clip.contentIDs == ["Icon", "BtnI"])
        #expect(clip.document.children.map(\.id) == ["Icon", "BtnI", "Btn"])
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("A node copied out of a component the copy also carries takes ids of its own")
    func nodeInsideCarriedDefinitionIsRenumbered() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Lbl", "BtnI"], from: document)
        let again = try PenClip.extract(nodeIDs: ["Lbl", "BtnI"], from: PenClipFixture.document())

        #expect(clip.contentIDs.count == 2)
        #expect(clip.contentIDs.first != "Lbl")
        #expect(clip.document.children.map(\.id).suffix(2) == ["Icon", "Btn"])
        #expect(clip == again)
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("The clip expands on its own, with nothing but itself")
    func clipExpandsAlone() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: document)

        let expanded = EditableDocument(from: clip.document).expanded(for: .canvas)
        let index = PenClipFixture.index(expanded.children)
        #expect(index["BtnI/IcoRef/Icon"] != nil)
        guard case let .text(label)? = index["BtnI/Lbl"]?.kind else {
            Issue.record("the instance's label did not expand")
            return
        }
        #expect(label.content == .literal("Buy"))
    }
}
