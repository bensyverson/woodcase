//
//  SwiftUIEmitterFreeTransformTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins how the SwiftUI emitter turns and flips a node its parent does not lay out: about
/// its `x`/`y` anchor, as Pen does (`project/2026-09-27-fidelity-gaps.md`, F4).
struct SwiftUIEmitterFreeTransformTests {
    @Test("A turned node placed by x/y turns about its top-leading corner, unframed, at its x/y")
    func turnedFreeNode() throws {
        let code = try body(child: ##"{"type": "rectangle", "id": "r", "x": 80, "y": 60, "width": 200, "height": 60, "rotation": -20, "fill": "#FF0000"}"##)
        #expect(code.contains(".rotationEffect(.degrees(20), anchor: .topLeading)\n"))
        #expect(code.contains(".offset(x: 80, y: 60)"))
        #expect(!code.contains(".frame(width: 208"))
    }

    @Test("A flipped node placed by x/y mirrors about its top-leading corner, before it turns")
    func flippedFreeNode() throws {
        let code = try body(child: ##"{"type": "rectangle", "id": "r", "x": 160, "y": 150, "width": 120, "height": 40, "flipX": true, "rotation": 30, "fill": "#FF0000"}"##)
        let flip = try #require(code.range(of: ".scaleEffect(x: -1, y: 1, anchor: .topLeading)"))
        let turn = try #require(code.range(of: ".rotationEffect(.degrees(-30), anchor: .topLeading)"))
        #expect(flip.lowerBound < turn.lowerBound)
    }

    @Test("A turned node in a flex flow keeps the centre pivot and its bounding-box frame")
    func turnedFlexChild() throws {
        let code = try body(
            child: ##"{"type": "rectangle", "id": "r", "width": 80, "height": 40, "rotation": 90, "fill": "#FF0000"}"##,
            layout: "horizontal"
        )
        #expect(code.contains(".rotationEffect(.degrees(-90))\n"))
        #expect(code.contains(".frame(width: 40, height: 80)"))
    }

    /// Emit a 2.19 document whose root frame, laid out by `layout`, holds `child`, and return
    /// the page's source.
    private func body(child: String, layout: String = "none") throws -> String {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "layout": "\##(layout)", "width": 400, "height": 300, "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
