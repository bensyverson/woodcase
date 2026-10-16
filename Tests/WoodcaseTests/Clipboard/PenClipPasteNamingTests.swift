//
//  PenClipPasteNamingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/plan(into:at:)`` reuses what the target already has, by name and
/// definition, and renames what collides — with every use in the paste following.
struct PenClipPasteNamingTests {
    @Test("Pasting twice into one document never duplicates a component")
    func twiceInOneDocument() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: source)
        let components = source.componentRegistry.count

        let first = try clip.plan(into: source, at: .inPlace)
        try PasteFixture.apply(first, to: source)
        let second = try clip.plan(into: source, at: .inPlace)
        try PasteFixture.apply(second, to: source)

        #expect(source.componentRegistry.count == components)
        for pasted in first.insertedRootIDs + second.insertedRootIDs {
            guard case let .ref(instance)? = source.nodes[pasted]?.kind else {
                Issue.record("a pasted instance is missing")
                continue
            }
            #expect(instance.ref == "Btn")
        }
        #expect(first.insertedRootIDs.count == 1 && second.insertedRootIDs.count == 1)
    }

    @Test("A second paste into another document reuses what the first brought, though its ids differ")
    func twiceAcrossDocuments() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: source)
        let target = PasteFixture.empty()
        let first = try clip.plan(into: target, at: .inPlace)
        try PasteFixture.apply(first, to: target)

        let second = try clip.plan(into: target, at: .centered(on: PenPoint(x: 900, y: 900), in: nil))
        try PasteFixture.apply(second, to: target)

        #expect(second.operations.count == 1)
        #expect(second.reusedVariables == ["accent", "brand"])
        let button = try #require(target.nodes.values.first { $0.common.name == "Button" })
        #expect(second.reusedComponents["Btn"] == button.id)
        let pasted = try #require(second.insertedRootIDs.first)
        let before = try #require(PasteFixture.render(source, nodeID: "BtnI"))
        let after = try #require(PasteFixture.render(target, nodeID: pasted))
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: after, and: before) < 0.01)
    }

    @Test("An instance's descendants keys follow a reused component to its ids")
    func descendantKeysFollowReusedComponent() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let target = PasteFixture.empty()
        try PasteFixture.apply(clip.plan(into: target, at: .inPlace), to: target)
        let label = try #require(target.nodes.values.first { $0.common.name == "Label" })

        let second = try clip.plan(into: target, at: .inPlace)

        guard case let .ref(instance)? = PasteFixture.inserts(second).first?.node.kind else {
            Issue.record("the pasted instance is not a ref")
            return
        }
        #expect(instance.descendants.map { Array($0.keys) } == [label.id])
    }

    @Test("A renamed variable is followed by the variables that reference it")
    func renamedVariableChain() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let target = try PasteFixture.document("""
        { "version": "2.17", "variables": { "brand": { "type": "color", "value": "#ABCDEF" } }, "children": [] }
        """)

        let plan = try clip.plan(into: target, at: .inPlace)

        let added = PasteFixture.addedVariables(plan)
        #expect(Set(added.keys) == ["accent", "brand-2"])
        #expect(added["accent"]?.value == .simple("$brand-2"))
        #expect(plan.renamedVariables == [PastePlan.Rename(from: "brand", to: "brand-2")])
    }

    @Test("A theme axis the target lacks is added; one it has is widened by the options it lacks")
    func themeAxes() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let narrow = try PasteFixture.document("""
        { "version": "2.17", "themes": { "mode": ["light", "sepia"] }, "children": [] }
        """)

        let intoEmpty = try clip.plan(into: PasteFixture.empty(), at: .inPlace)
        let intoNarrow = try clip.plan(into: narrow, at: .inPlace)

        #expect(intoEmpty.operations.first == .addThemeAxis(EditOperation.AddThemeAxis(
            name: "mode", options: ["light", "dark"]
        )))
        #expect(intoNarrow.operations.first == .updateThemeAxis(EditOperation.UpdateThemeAxis(
            name: "mode", options: ["light", "sepia", "dark"]
        )))
    }

    @Test("A copied component is a new component, renamed when its name is taken")
    func copiedComponentIsRenamed() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["Btn"], from: source)

        let plan = try clip.plan(into: source, at: .inPlace)

        #expect(plan.reusedComponents == ["Icon": "Icon"])
        #expect(plan.renamedComponents == [PastePlan.Rename(from: "Button", to: "Button 2")])
        let pasted = try #require(PasteFixture.inserts(plan).first?.node)
        #expect(pasted.common.name == "Button 2")
        #expect(pasted.common.reusable == true)
    }

    @Test("A library component the target imports too is reused, not copied")
    func importedComponentIsReused() throws {
        let document = try EditableDocumentLibrariesTests.document().0
        let clip = try PenClip.extract(nodeIDs: ["Ins02"], from: document)

        let plan = try clip.plan(into: document, at: .inPlace)

        #expect(plan.operations.count == 1)
        guard case let .ref(instance)? = PasteFixture.inserts(plan).first?.node.kind else {
            Issue.record("the pasted instance is not a ref")
            return
        }
        #expect(instance.ref == "K:Card1")
    }

    @Test("A library component pasted where the library is not imported becomes a local definition")
    func importedComponentBecomesLocal() throws {
        let clip = try PenClip.extract(nodeIDs: ["Ins02"], from: EditableDocumentLibrariesTests.document().0)
        let target = PasteFixture.empty()

        let plan = try clip.plan(into: target, at: .inPlace)
        try PasteFixture.apply(plan, to: target)

        let pasted = try #require(plan.insertedRootIDs.first)
        guard case let .ref(instance)? = target.nodes[pasted]?.kind else {
            Issue.record("the pasted instance is not a ref")
            return
        }
        #expect(target.componentRegistry[instance.ref] != nil)
        #expect(target.variables?["K:accent"] != nil)
    }
}
