//
//  ReactEmitterImageTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

@Suite("ReactEmitter Image Collection")
struct ReactEmitterImageTests {
    @Test("Node with image fill collects URL")
    func nodeWithImageFill() {
        let node = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "bg"),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.image(PenFill.PenImageFill(url: "./images/photo.png")))
            ))
        )
        let urls = ReactEmitter.collectImageURLs(from: node)
        #expect(urls == ["./images/photo.png"])
    }

    @Test("Nested frame child with image fill is collected")
    func nestedFrameChild() {
        let node = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "wrapper"),
            kind: .frame(PenNode.FrameData(
                children: [
                    PenNode(
                        id: "r1",
                        common: PenNodeCommon(name: "bg"),
                        kind: .rectangle(PenNode.RectangleData(
                            fills: .single(.image(PenFill.PenImageFill(url: "./images/hero.jpg")))
                        ))
                    ),
                ]
            ))
        )
        let urls = ReactEmitter.collectImageURLs(from: node)
        #expect(urls == ["./images/hero.jpg"])
    }

    @Test("No images returns empty set")
    func noImages() {
        let node = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "box"),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.color(PenFill.PenColorFill(color: .literal("#FF0000"))))
            ))
        )
        let urls = ReactEmitter.collectImageURLs(from: node)
        #expect(urls.isEmpty)
    }

    @Test("Multiple images are collected as union")
    func multipleImages() {
        let node = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "wrapper"),
            kind: .frame(PenNode.FrameData(
                children: [
                    PenNode(
                        id: "r1",
                        common: PenNodeCommon(name: "bg1"),
                        kind: .rectangle(PenNode.RectangleData(
                            fills: .single(.image(PenFill.PenImageFill(url: "./images/a.png")))
                        ))
                    ),
                    PenNode(
                        id: "r2",
                        common: PenNodeCommon(name: "bg2"),
                        kind: .ellipse(PenNode.EllipseData(
                            fills: .single(.image(PenFill.PenImageFill(url: "./images/b.png")))
                        ))
                    ),
                ]
            ))
        )
        let urls = ReactEmitter.collectImageURLs(from: node)
        #expect(urls == ["./images/a.png", "./images/b.png"])
    }

    @Test("emit() populates imageAssetURLs from component source nodes")
    func emitCollectsImageURLs() {
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "c1",
                common: PenNodeCommon(name: "Component/Card", reusable: true, metadata: ["type": "component"]),
                kind: .frame(PenNode.FrameData(
                    layout: .vertical,
                    children: [
                        PenNode(
                            id: "r1",
                            common: PenNodeCommon(name: "bg"),
                            kind: .rectangle(PenNode.RectangleData(
                                fills: .single(.image(PenFill.PenImageFill(url: "./images/card-bg.png")))
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let components = ComponentAnalyzer.analyze(doc)
        let theme = ThemeAnalyzer.analyze(doc)
        let result = ReactEmitter.emit(document: doc, components: components, theme: theme)
        #expect(result.imageAssetURLs.contains("./images/card-bg.png"))
    }
}
