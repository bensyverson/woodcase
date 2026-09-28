//
//  ReactEmitterBrowserTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A `browser` node becomes an `<iframe>` of the page, sized and placed like any other
/// leaf (ruling, Ben, 2026-09-26). Pen stores `https://example.com` as `example.com`,
/// so the emitter restores the scheme; the node's name titles the frame for
/// assistive technology.
struct ReactEmitterBrowserTests {
    private func emit(_ data: PenNode.BrowserData, name: String? = "Preview") -> String {
        let doc = PenDocument(children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(id: "web1", common: PenNodeCommon(name: name), kind: .browser(data)),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        return ReactEmitter.emit(document: doc, components: components, theme: theme).files[0].content
    }

    @Test("A browser is an iframe of its page, with the https scheme Pen strips restored")
    func iframeWithRestoredScheme() {
        let content = emit(PenNode.BrowserData(url: "example.com", width: .fixed(200), height: .fixed(90)))
        #expect(content.contains("<iframe"))
        #expect(content.contains(#"src="https://example.com""#))
        #expect(!content.contains("unsupported node type"))
    }

    @Test("An address with its own scheme is kept as written")
    func explicitSchemeKept() {
        let content = emit(PenNode.BrowserData(url: "http://localhost:3000/app"))
        #expect(content.contains(#"src="http://localhost:3000/app""#))
    }

    @Test("The frame is titled by the node's name, then its address, then its type")
    func title() {
        #expect(emit(PenNode.BrowserData(url: "example.com")).contains(#"title="Preview""#))
        #expect(emit(PenNode.BrowserData(url: "example.com"), name: nil).contains(#"title="https://example.com""#))
        #expect(emit(PenNode.BrowserData(), name: nil).contains(#"title="browser""#))
    }

    @Test("An empty address emits a sized iframe with no src, holding the node's place")
    func emptyAddress() {
        let content = emit(PenNode.BrowserData(url: "", width: .fixed(200), height: .fixed(90)))
        #expect(content.contains("<iframe"))
        #expect(!content.contains("src="))
        #expect(content.contains("width: 200"))
        #expect(content.contains("height: 90"))
    }

    @Test("Size, corner radius and clipping ride the style object; the browser's own border is removed")
    func styles() {
        let content = emit(PenNode.BrowserData(
            url: "example.com", cornerRadius: .uniform(.literal(12)),
            width: .fillContainer(fallback: nil), height: .fixed(120)
        ))
        #expect(content.contains(#"width: "100%""#))
        #expect(content.contains("height: 120"))
        #expect(content.contains("borderRadius: 12"))
        #expect(content.contains(#"overflow: "hidden""#))
        #expect(content.contains(#"border: "none""#))
    }

    @Test("A stroke and a shadow are emitted as on any other shape")
    func strokeAndEffects() {
        let content = emit(PenNode.BrowserData(
            url: "example.com",
            stroke: .single(.shorthand("#10B981")), strokeWidth: .uniform(.literal(2)),
            effects: .single(.shadow(PenEffect.PenShadowEffect(blur: .literal(8), color: .literal("#00000033"))))
        ))
        #expect(content.contains("#10B981"))
        #expect(content.contains("boxShadow"))
    }

    @Test("Device, zoom and scroll have no iframe equivalent and are not emitted")
    func viewportKeysDropped() {
        let content = emit(PenNode.BrowserData(url: "example.com", deviceId: "iphone-15", zoom: 2, scrollX: 5, scrollY: 240))
        #expect(content.contains("<iframe"))
        #expect(!content.contains("iphone-15"))
        #expect(!content.contains("zoom"))
        #expect(!content.contains("240"))
    }

    @Test("An address a JSX string cannot hold is emitted as a JavaScript string expression")
    func escapedAddress() {
        let content = emit(PenNode.BrowserData(url: #"example.com/?q="a"&b={c}"#), name: #"Say "hi""#)
        #expect(content.contains(#"src={"https://example.com/?q=\"a\"&b={c}"}"#))
        #expect(content.contains(#"title={"Say \"hi\""}"#))
    }
}
