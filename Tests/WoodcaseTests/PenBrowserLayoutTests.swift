//
//  PenBrowserLayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A `browser` node is a sized leaf: it lays out exactly as a rectangle with the same
/// `width`/`height` does, so a column holding one measures the page's height rather
/// than skipping it.
struct PenBrowserLayoutTests {
    private func fixtureRects() throws -> [String: PenRect] {
        let url = try #require(Bundle.module.url(forResource: "browser", withExtension: "pen", subdirectory: "Fixtures"))
        return try PenLayoutEngine.layout(PenParser.parse(contentsOf: url))
    }

    @Test("A fixed-size browser lays out at its declared width and height")
    func fixedSize() throws {
        let rects = try fixtureRects()
        #expect(rects["BrDev"] == PenRect(x: 10, y: 190, width: 300, height: 90))
        #expect(rects["BrBlk"] == PenRect(x: 10, y: 290, width: 300, height: 60))
    }

    @Test("A fill_container browser takes its parent's inner width")
    func fillContainer() throws {
        let rects = try fixtureRects()
        #expect(rects["BrWeb"] == PenRect(x: 10, y: 60, width: 300, height: 120))
    }

    @Test("A fit_content column counts every browser's height, and later siblings follow them")
    func fitContentColumn() throws {
        let rects = try fixtureRects()
        // 10 padding + 40 + 120 + 90 + 60 + 20 + 4 gaps of 10 + 10 padding.
        #expect(rects["BrRt0"]?.height == 390)
        #expect(rects["BrBot"]?.y == 360)
    }

    @Test("A browser sizes exactly as a rectangle with the same width and height", arguments: [
        (PenSizing.fixed(120), PenSizing.fixed(40)),
        (.fillContainer(fallback: nil), .fixed(40)),
        (.fixed(120), .fillContainer(fallback: nil)),
        (.fitContent(fallback: 50), .fitContent(fallback: nil)),
    ])
    func matchesRectangle(width: PenSizing, height: PenSizing) {
        func rect(of kind: PenNode.Kind) -> PenRect? {
            let parent = PenNode(
                id: "P", common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(200), height: .fixed(100), layout: .vertical,
                    children: [PenNode(id: "C", common: PenNodeCommon(), kind: kind)]
                ))
            )
            return PenLayoutEngine.layout(PenDocument(children: [parent]))["C"]
        }
        let browser = rect(of: .browser(PenNode.BrowserData(width: width, height: height)))
        let rectangle = rect(of: .rectangle(PenNode.RectangleData(width: width, height: height)))
        #expect(browser == rectangle)
    }
}
