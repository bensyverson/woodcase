//
//  ComponentDefinitionRelayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Editing a component definition re-lays out its instances in other roots.
///
/// The layout cache records dirty nodes by *source* id, but every instance of a
/// component lays out under `<ref>/<id>` in another root — so a change to the
/// definition named no expanded node, and the boards drawing it kept their old rects
/// (leaf `bDA99O`, design `project/2026-10-04-sub-root-layout-design.md`).
@MainActor
struct ComponentDefinitionRelayoutTests {
    /// A text long enough to wrap inside the card's 200-point width.
    private static let longText = "A card body long enough to wrap over several lines"

    @Test("Editing a text inside a component re-lays out its instance in another root")
    func definitionTextEdit() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.applyAndLayOut(.setProperties(EditOperation.SetProperties(
            nodeID: "cardBodyText", properties: ["kind.content": .string(Self.longText)]
        )))
    }

    @Test("Resizing a component's root re-lays out its instances, nested ones included")
    func definitionResize() throws {
        let fixture = try StructuralLayoutFixture()
        try fixture.applyAndLayOut(.setProperties(EditOperation.SetProperties(
            nodeID: "Card", properties: ["kind.width": .double(320)]
        )))
    }

    @Test("A host pipeline's incremental layout re-lays out the instance too")
    func hostPipeline() throws {
        let fixture = try StructuralLayoutFixture()
        let measurer = fixture.recorder.measurer
        try fixture.document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "cardBodyText", properties: ["kind.content": .string(Self.longText)]
        )))
        let resolved = PenVariableResolver.resolve(fixture.document.expandedDocument().0)
        let incremental = fixture.document.layoutIncremental(document: resolved, textMeasurer: measurer)
        #expect(incremental == LayoutOracle.fullLayout(of: fixture.document, textMeasurer: measurer))
    }
}
