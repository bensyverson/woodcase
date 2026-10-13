//
//  PenClipVariableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/extract(nodeIDs:from:)`` carries the variables the copy uses, the
/// variables those reference, and the theme axes they need — and nothing else.
struct PenClipVariableTests {
    @Test("A variable carries the variables it references and its theme axis")
    func variableCarriesChainAndAxis() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Icon"], from: document)

        #expect(clip.document.variables?.keys.sorted() == ["accent", "brand"])
        #expect(clip.document.variables?["brand"] == document.variables?["brand"])
        #expect(clip.document.themes == ["mode": ["light", "dark"]])
    }

    @Test("Variables used only inside a carried component come along")
    func componentVariablesComeAlong() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: document)

        #expect(clip.document.variables?.keys.sorted() == ["accent", "brand"])
        #expect(clip.document.themes?.keys.sorted() == ["mode"])
    }

    @Test("A copy that uses no variable carries none, and no theme axis")
    func noVariables() throws {
        let document = try PenClipFixture.document()

        let clip = try PenClip.extract(nodeIDs: ["Free"], from: document)

        #expect(clip.contentIDs == ["Free"])
        #expect(clip.document.variables == nil)
        #expect(clip.document.themes == nil)
    }

    @Test("A theme a node pins comes along with every option of its axis")
    func pinnedThemeComesAlong() throws {
        let document = try PenClipFixture.document()
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Free", properties: ["common.theme": .dictionary(["density": .string("tight")])]
        )))

        let clip = try PenClip.extract(nodeIDs: ["Free"], from: document)

        #expect(clip.document.themes == ["density": ["comfy", "tight"]])
    }
}
