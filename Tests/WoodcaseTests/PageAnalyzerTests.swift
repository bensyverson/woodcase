//
//  PageAnalyzerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PageAnalyzerTests {
    // MARK: - Helpers

    private func makeDocument(children: [PenNode] = []) -> PenDocument {
        PenDocument(version: "2.9", children: children)
    }

    private func makeFrame(
        id: String = "frame1",
        name: String? = nil,
        reusable: Bool? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, reusable: reusable),
            kind: .frame(PenNode.FrameData(layout: .vertical, children: children))
        )
    }

    private func makeRef(
        id: String = "ref1",
        name: String? = nil,
        ref: String,
        descendants: [String: PenDescendantOverride]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .ref(PenNode.RefData(ref: ref, descendants: descendants))
        )
    }

    // MARK: - Page Detection

    @Test("Finds non-reusable top-level frames as pages")
    func findsPages() {
        let doc = makeDocument(children: [
            makeFrame(id: "page1", name: "Home"),
            makeFrame(id: "comp1", name: "Component/Card", reusable: true),
            makeFrame(id: "page2", name: "Settings"),
        ])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages.count == 2)
        #expect(pages[0].name == "Home")
        #expect(pages[1].name == "Settings")
    }

    @Test("Excludes reusable frames")
    func excludesReusable() {
        let doc = makeDocument(children: [
            makeFrame(id: "comp1", name: "Component/Card", reusable: true),
            makeFrame(id: "comp2", name: "Component/Button", reusable: true),
        ])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages.isEmpty)
    }

    @Test("Excludes non-frame top-level nodes")
    func excludesNonFrames() {
        let textNode = PenNode(
            id: "text1",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData(content: .literal("Hello")))
        )
        let doc = makeDocument(children: [textNode])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages.isEmpty)
    }

    @Test("Sanitizes page names with Screen prefix")
    func sanitizesScreenPrefix() {
        let doc = makeDocument(children: [
            makeFrame(id: "p1", name: "Component/Screen/Settings"),
        ])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages[0].name == "Settings")
    }

    @Test("Excludes state variant siblings from pages")
    func excludesStateVariants() {
        let doc = makeDocument(children: [
            makeFrame(id: "toggle", name: "Toggle", reusable: true),
            makeFrame(id: "toggle-off", name: "Toggle:off"),
            makeFrame(id: "page1", name: "Home"),
        ])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages.count == 1)
        #expect(pages[0].name == "Home")
    }

    @Test("Excludes a frame a component's _states names from pages")
    func excludesStatesMetadataVariants() {
        let chip = PenNode(
            id: "chip",
            common: PenNodeCommon(
                name: "Chip", reusable: true, metadata: ["_states": .dictionary(["selected": .string("chip-on")])]
            ),
            kind: .frame(PenNode.FrameData())
        )
        let doc = makeDocument(children: [chip, makeFrame(id: "chip-on", name: "Chip selected"), makeFrame(id: "page1", name: "Home")])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages.map(\.name) == ["Home"])
    }

    // MARK: - Naming

    @Test("A page keeps a camel-case frame name's inner capitals, as a component does")
    func keepsInnerCapitals() {
        let doc = makeDocument(children: [makeFrame(id: "p1", name: "FilledCard")])

        #expect(PageAnalyzer.analyze(doc).map(\.name) == ["FilledCard"])
    }

    @Test("A page and a component of the same frame name are named by one rule")
    func oneRuleForPagesAndComponents() {
        for raw in ["FilledCard", "filledCard", "Filled card", "Component/Tab Bar/Home Active", "2up"] {
            let page = PageAnalyzer.analyze(makeDocument(children: [makeFrame(id: "p", name: raw)]))
            let component = ComponentAnalyzer.analyze(makeDocument(children: [makeFrame(id: "c", name: raw, reusable: true)]))
            #expect(page.map(\.name) == component.map(\.name), "\(raw)")
        }
    }

    @Test("A page named like a component is suffixed Page, so a page file can import the component")
    func pageNamedLikeAComponent() {
        let doc = makeDocument(children: [
            makeFrame(id: "comp", name: "FilledCard", reusable: true),
            makeFrame(id: "page", name: "FilledCard"),
        ])

        #expect(PageAnalyzer.analyze(doc).map(\.name) == ["FilledCardPage"])
    }

    @Test("Pages whose names differ only in case are numbered, so their files do not collide on a case-insensitive disk")
    func pagesDifferingInCase() {
        let doc = makeDocument(children: [
            makeFrame(id: "a", name: "FilledCard"),
            makeFrame(id: "b", name: "Filledcard"),
            makeFrame(id: "c", name: "Filled card"),
        ])

        let names = PageAnalyzer.analyze(doc).map(\.name)

        #expect(Set(names.map { $0.lowercased() }).count == 3)
        #expect(Set(names) == ["FilledCard", "Filledcard2", "FilledCard3"])
    }

    @Test("Two pages of one name are numbered in document order")
    func duplicatePageNames() {
        let doc = makeDocument(children: [
            makeFrame(id: "first", name: "Home"),
            makeFrame(id: "second", name: "Home"),
        ])

        let pages = PageAnalyzer.analyze(doc)

        #expect(pages.map(\.id) == ["first", "second"])
        #expect(pages.map(\.name) == ["Home", "Home2"])
    }

    // MARK: - Referenced Components

    @Test("Finds referenced component IDs in page tree")
    func findsReferencedComponents() {
        let page = makeFrame(
            id: "page1",
            name: "Home",
            children: [
                makeRef(id: "r1", ref: "comp1"),
                makeRef(id: "r2", ref: "comp2"),
                makeFrame(id: "inner", name: "Section", children: [
                    makeRef(id: "r3", ref: "comp1"),
                ]),
            ]
        )

        let ids = PageAnalyzer.referencedComponentIDs(in: page)

        #expect(ids == Set(["comp1", "comp2"]))
    }

    @Test("Returns empty set when no refs in page")
    func noRefsReturnsEmpty() {
        let page = makeFrame(id: "page1", name: "Home")

        let ids = PageAnalyzer.referencedComponentIDs(in: page)

        #expect(ids.isEmpty)
    }
}
