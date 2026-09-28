//
//  ReactEmitterViewBoxTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The emitted `<svg>` for a path node must carry the node's `viewBox` when it
/// has one, so the browser performs the same coordinate mapping the renderer does.
struct ReactEmitterViewBoxTests {
    private func emitPath(_ data: PenNode.PathData) -> String {
        let doc = PenDocument(children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(id: "path1", common: PenNodeCommon(), kind: .path(data)),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        return ReactEmitter.emit(document: doc, components: components, theme: theme).files[0].content
    }

    /// Pen maps a path's tight bounds onto its box when it declares no viewBox, as the
    /// renderer does (``PenPath/sourceRegion(viewBox:)``), so the emitted SVG names those
    /// bounds as its viewBox. This test once pinned the node box instead, which drew the
    /// geometry at its own size where Pen stretches it (`render-fill-domains`' `curve-v`).
    @Test("A path without a viewBox maps its tight bounds onto the box")
    func withoutViewBox() {
        let content = emitPath(PenNode.PathData(
            width: .fixed(200),
            height: .fixed(100),
            geometry: "M10 10l80 0-40 80z",
            fills: .single(.shorthand("#000"))
        ))
        #expect(content.contains("viewBox=\"10 10 80 80\" preserveAspectRatio=\"none\""))
    }

    @Test("A path with a viewBox emits it verbatim")
    func withViewBox() {
        let content = emitPath(PenNode.PathData(
            width: .fixed(200),
            height: .fixed(200),
            geometry: "M10 10l80 0-40 80z",
            viewBox: PenViewBox(x: 25, y: 25, width: 50, height: 50),
            fills: .single(.shorthand("#00AA00"))
        ))
        #expect(content.contains("viewBox=\"25 25 50 50\""))
    }

    @Test("A path with a viewBox disables aspect-ratio preservation and clipping")
    func viewBoxStretchesAndOverflows() {
        let content = emitPath(PenNode.PathData(
            width: .fixed(200),
            height: .fixed(100),
            geometry: "M10 10l80 0-40 80z",
            viewBox: PenViewBox(x: 0, y: 0, width: 100, height: 100),
            fills: .single(.shorthand("#AA00AA"))
        ))
        #expect(content.contains("viewBox=\"0 0 100 100\""))
        #expect(content.contains("preserveAspectRatio=\"none\""))
        #expect(content.contains("overflow=\"visible\""))
    }
}
