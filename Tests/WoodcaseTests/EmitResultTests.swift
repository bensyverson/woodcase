//
//  EmitResultTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

@Suite("EmitResult")
struct EmitResultTests {
    @Test("EmitResult round-trips through Codable")
    func codableRoundTrip() throws {
        let original = EmitResult(
            files: [GeneratedFile(path: "test.tsx", content: "hello")],
            iconLibraries: ["lucide"],
            imageAssetURLs: ["./images/photo.png"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EmitResult.self, from: data)
        #expect(decoded == original)
    }

    @Test("emit() with lucide icons returns iconLibraries containing lucide")
    func emitWithLucideIcons() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/IconCard", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "icon1",
                            common: PenNodeCommon(name: "icon"),
                            kind: .icon(PenNode.IconData(
                                icon: .literal("arrow-left"),
                                library: .literal("lucide"),
                                width: .fixed(24),
                                height: .fixed(24)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let result = ReactEmitter.emit(document: doc, components: components, theme: theme)

        #expect(result.iconLibraries.contains("lucide"))
        #expect(!result.files.isEmpty)
    }

    @Test("emit() with no icons returns empty iconLibraries")
    func emitWithNoIcons() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Plain", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(layout: .vertical))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)

        let result = ReactEmitter.emit(document: doc, components: components, theme: theme)

        #expect(result.iconLibraries.isEmpty)
    }
}
