//
//  ReactEmitterRefInliningTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ReactEmitterRefInliningTests {
    // MARK: - Helpers

    /// Build a minimal component + ref scenario and emit, returning the component TSX output for the page.
    private func emitPage(
        componentNode: PenNode,
        refNode: PenNode,
        componentProps _: [String: AnyCodable] = [:],
        options: ReactEmitter.Options = ReactEmitter.Options(),
        diagnostics: PenDiagnosticCollector? = nil
    ) -> String {
        let doc = PenDocument(version: "2.9", children: [
            componentNode,
            PenNode(
                id: "page1",
                common: PenNodeCommon(name: "TestPage"),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [refNode]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let result = ReactEmitter.emit(
            document: doc, components: components, pages: pages,
            theme: theme, options: options, diagnostics: diagnostics
        )
        return result.files.first { $0.path == "pages/TestPage.tsx" }?.content ?? ""
    }

    // MARK: - Tests

    @Test("Ref with unmapped overrides inlines component instead of emitting tag")
    func refWithUnmappedOverridesInlines() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/StatusIndicator", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(
                layout: .horizontal,
                children: [
                    PenNode(
                        id: "dot",
                        common: PenNodeCommon(name: "Dot"),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fixed(8), height: .fixed(8),
                            fills: PenFills.single(.shorthand("#00FF00"))
                        ))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "StatusIndicator"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "dot": PenDescendantOverride(properties: ["fill": .string("#FF0000")]),
                ]
            ))
        )

        let output = emitPage(componentNode: component, refNode: ref)

        // Should NOT contain component tag — it should be inlined
        // ComponentAnalyzer sanitizes "Component/StatusIndicator" → preserves casing
        #expect(!output.contains("<StatusIndicator"))
        // Should contain customization comment and inlined nodes
        #expect(output.contains("Customized from: StatusIndicator"))
        #expect(output.contains("<div"))
    }

    @Test("Inlined ref emits customization comment")
    func inlinedRefEmitsComment() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/StatusIndicator", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(
                layout: .horizontal,
                children: [
                    PenNode(
                        id: "dot",
                        common: PenNodeCommon(name: "Dot"),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fixed(8), height: .fixed(8),
                            fills: PenFills.single(.shorthand("#00FF00"))
                        ))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "StatusIndicator"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "dot": PenDescendantOverride(properties: ["fill": .string("#FF0000")]),
                ]
            ))
        )

        let output = emitPage(componentNode: component, refNode: ref)

        #expect(output.contains("{/* Customized from: StatusIndicator */}"))
    }

    @Test("Ref with all overrides mapped to props emits component tag")
    func refWithMappedOverridesEmitsTag() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Label", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary(["title": .string("Title")]),
            ]),
            kind: .frame(PenNode.FrameData(
                layout: .horizontal,
                children: [
                    PenNode(
                        id: "titleNode",
                        common: PenNodeCommon(name: "Title"),
                        kind: .text(PenNode.TextData(content: .literal("Default")))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Label"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "titleNode": PenDescendantOverride(properties: ["content": .string("Custom")]),
                ]
            ))
        )

        let output = emitPage(componentNode: component, refNode: ref)

        // Should contain <Label tag (not inlined)
        #expect(output.contains("<Label"))
        // Should NOT contain customization comment
        #expect(!output.contains("Customized from"))
    }

    @Test("Ref with mixed mapped and unmapped overrides inlines")
    func refWithMixedOverridesInlines() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary(["title": .string("Title")]),
            ]),
            kind: .frame(PenNode.FrameData(
                layout: .vertical,
                children: [
                    PenNode(
                        id: "titleNode",
                        common: PenNodeCommon(name: "Title"),
                        kind: .text(PenNode.TextData(content: .literal("Default")))
                    ),
                    PenNode(
                        id: "bg",
                        common: PenNodeCommon(name: "Background"),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fillContainer(fallback: nil), height: .fixed(100),
                            fills: PenFills.single(.shorthand("#FFFFFF"))
                        ))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "titleNode": PenDescendantOverride(properties: ["content": .string("Custom Title")]),
                    "bg": PenDescendantOverride(properties: ["fill": .string("#000000")]),
                ]
            ))
        )

        let output = emitPage(componentNode: component, refNode: ref)

        // Mixed: bg has no prop mapping → inline
        #expect(!output.contains("<Card"))
        #expect(output.contains("Customized from: Card"))
    }

    @Test("Warning diagnostic emitted for inlined ref")
    func warningDiagnosticEmitted() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Badge", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(
                layout: .horizontal,
                children: [
                    PenNode(
                        id: "icon",
                        common: PenNodeCommon(name: "Icon"),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fixed(16), height: .fixed(16),
                            fills: PenFills.single(.shorthand("#0000FF"))
                        ))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Badge"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "icon": PenDescendantOverride(properties: ["fill": .string("#FF0000")]),
                ]
            ))
        )

        let collector = PenDiagnosticCollector()
        _ = emitPage(componentNode: component, refNode: ref, diagnostics: collector)

        #expect(collector.hasIssues)
        let diag = collector.diagnostics.first
        #expect(diag?.stage == .codeGen)
        #expect(diag?.severity == .warning)
        #expect(diag?.message.contains("Badge") == true)
    }

    @Test("Strict mode promotes inlining diagnostic to error")
    func strictModePromotesToError() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Badge", reusable: true, metadata: ["type": "component"]),
            kind: .frame(PenNode.FrameData(
                layout: .horizontal,
                children: [
                    PenNode(
                        id: "icon",
                        common: PenNodeCommon(name: "Icon"),
                        kind: .rectangle(PenNode.RectangleData(
                            width: .fixed(16), height: .fixed(16),
                            fills: PenFills.single(.shorthand("#0000FF"))
                        ))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Badge"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "icon": PenDescendantOverride(properties: ["fill": .string("#FF0000")]),
                ]
            ))
        )

        let collector = PenDiagnosticCollector()
        let options = ReactEmitter.Options(strict: true)
        _ = emitPage(componentNode: component, refNode: ref, options: options, diagnostics: collector)

        #expect(collector.hasErrors)
        let diag = collector.diagnostics.first
        #expect(diag?.severity == .error)
    }

    @Test("Component ref with fixed-width root emits flexShrink: 0")
    func refWithFixedWidthRootEmitsFlexShrink() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary(["title": .string("Title")]),
            ]),
            kind: .frame(PenNode.FrameData(
                width: .fixed(160),
                layout: .vertical,
                children: [
                    PenNode(
                        id: "titleNode",
                        common: PenNodeCommon(name: "Title"),
                        kind: .text(PenNode.TextData(content: .literal("Default")))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "titleNode": PenDescendantOverride(properties: ["content": .string("Custom")]),
                ]
            ))
        )

        let output = emitPage(componentNode: component, refNode: ref)

        // Should emit as component tag (not inlined)
        #expect(output.contains("<Card"))
        // Should include flexShrink: 0 to prevent CSS flex from shrinking
        #expect(output.contains("flexShrink: 0"))
    }

    @Test("Component with imageURL prop uses prop variable in template")
    func imageURLPropUsesVariable() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: [
                "type": "component",
                "_props": .dictionary(["image": .string("Image")]),
            ]),
            kind: .frame(PenNode.FrameData(
                width: .fixed(160),
                layout: .vertical,
                children: [
                    PenNode(
                        id: "imageNode",
                        common: PenNodeCommon(name: "Image"),
                        kind: .frame(PenNode.FrameData(
                            width: .fillContainer(fallback: nil),
                            height: .fixed(90),
                            fills: PenFills.single(.image(PenFill.PenImageFill(
                                url: "./images/default.png", mode: .cover
                            )))
                        ))
                    ),
                ]
            ))
        )

        let ref = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Card"),
            kind: .ref(PenNode.RefData(
                ref: "comp1",
                descendants: [
                    "imageNode": PenDescendantOverride(properties: [
                        "fill": .dictionary([
                            "type": .string("image"),
                            "url": .string("./images/custom.png"),
                            "mode": .string("fill"),
                        ]),
                    ]),
                ]
            ))
        )

        // Check the component template uses the prop variable, not the hardcoded URL
        let doc = PenDocument(version: "2.9", children: [
            component,
            PenNode(
                id: "page1",
                common: PenNodeCommon(name: "TestPage"),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [ref]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let pages = PageAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let result = ReactEmitter.emit(
            document: doc, components: components, pages: pages,
            theme: theme
        )

        let componentFile = result.files.first { $0.path.contains("Card.tsx") }
        let content = componentFile?.content ?? ""

        // Template should use prop variable in backgroundImage, not hardcode the URL
        #expect(content.contains("${image}"))
        // The default value in the function signature is fine, but the template body
        // should not contain the hardcoded URL
        #expect(!content.contains("url('./images/default.png')"))
    }
}
