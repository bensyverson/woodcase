//
//  ReactEmitterSharedPropTargetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A component whose `_props` point two entries at one descendant.
///
/// This used to be a hard crash rather than a bad emission: the node-id lookup was built
/// with `Dictionary(uniqueKeysWithValues:)`, so a second prop naming a node another prop
/// already named trapped with `Duplicate values for key`. The lookup is only reached
/// when an instance carries a descendant override, which is why `generate react` on the
/// definition alone exited 0 and the crash arrived the first time somebody overrode
/// anything.
///
/// Nothing here asserts a *crash*: a trap kills the test process, so the red run of these
/// tests is a dead runner rather than a failure report. What they assert is the emission
/// on the other side of it.
struct ReactEmitterSharedPropTargetTests {
    // MARK: - Helpers

    /// A StatCard whose `label` and `width` props both name `Body/Title`, mirroring
    /// `Fixtures/component-props.pen`, plus a page holding one instance of it.
    private func document(
        descendants: [String: PenDescendantOverride]
    ) -> PenDocument {
        let title = PenNode(
            id: "Ttl01",
            common: PenNodeCommon(name: "Title"),
            kind: .text(PenNode.TextData(content: .literal("Total")))
        )
        let body = PenNode(
            id: "Bdy01",
            common: PenNodeCommon(name: "Body"),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [title]))
        )
        let statCard = PenNode(
            id: "Stc01",
            common: PenNodeCommon(name: "StatCard", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary([
                    "label": .string("Body/Title"),
                    "width": .string("Body/Title"),
                ]),
            ]),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [body]))
        )
        let instance = PenNode(
            id: "Crd01",
            common: PenNodeCommon(name: "Card"),
            kind: .ref(PenNode.RefData(ref: "Stc01", descendants: descendants))
        )
        let page = PenNode(
            id: "Pag01",
            common: PenNodeCommon(name: "Page"),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: [instance]))
        )
        return PenDocument(version: "2.17", children: [page, statCard])
    }

    private func pageSource(descendants: [String: PenDescendantOverride]) throws -> String {
        let doc = document(descendants: descendants)
        let files = ReactEmitter.emit(
            document: doc,
            components: ComponentAnalyzer.analyze(doc),
            pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        ).files
        return try #require(files.first { $0.path == "pages/Page.tsx" }).content
    }

    // MARK: - Tests

    @Test("An instance overriding a descendant two props share emits a tag, not a trap")
    func sharedTargetWithAnOverrideEmits() throws {
        let source = try pageSource(descendants: [
            "Ttl01": PenDescendantOverride(properties: ["content": .string("Hello")]),
        ])

        #expect(source.contains("<StatCard label=\"Hello\" />"))
    }

    @Test("The shared descendant contributes one attribute, not one per prop")
    func sharedTargetEmitsOneAttribute() throws {
        let source = try pageSource(descendants: [
            "Ttl01": PenDescendantOverride(properties: ["content": .string("Hello")]),
        ])

        #expect(!source.contains("width="))
    }

    @Test("A shared descendant still counts as mapped, so the instance is not inlined")
    func sharedTargetIsNotInlined() throws {
        let source = try pageSource(descendants: [
            "Ttl01": PenDescendantOverride(properties: ["content": .string("Hello")]),
        ])

        #expect(!source.contains("Customized from:"))
    }

    @Test("An override of a descendant no prop names still inlines")
    func anUnmappedOverrideStillInlines() throws {
        let source = try pageSource(descendants: [
            "Bdy01": PenDescendantOverride(properties: ["fill": .string("#FF0000")]),
        ])

        #expect(source.contains("Customized from: StatCard"))
    }

    @Test("The definition alone emits without reaching the lookup")
    func theDefinitionAloneEmits() throws {
        let source = try pageSource(descendants: [:])

        #expect(source.contains("<StatCard />"))
    }
}
