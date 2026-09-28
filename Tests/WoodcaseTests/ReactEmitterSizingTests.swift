//
//  ReactEmitterSizingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter sizes a node where CSS alone would not land on Pen's size: a
/// `fit_content(N)` side with nothing to fit, a `fill_container(N)` side with no container
/// to fill, a `layout: "none"` frame (which never fits its children), and a frame whose
/// cross-axis size is left to fit its content where CSS would stretch it.
struct ReactEmitterSizingTests {
    // MARK: - Helpers

    /// The emitted `Box` component for a document whose one reusable root frame is `root`,
    /// a JSON object body without the braces' outer `type`, `id`, `name` and `reusable`.
    private func emitBox(_ root: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Box01", "name": "Box", "reusable": true, \(root)}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Box.tsx" }).content
    }

    // MARK: - fit_content fallbacks

    @Test("fit_content(N) on a frame with no children is N")
    func fitFallbackOnEmptyFrame() throws {
        let content = try emitBox(##""width": "fit_content(200)", "height": "fit_content(100)", "fill": "#F0F0F0""##)
        #expect(content.contains("width: 200,"))
        #expect(content.contains("height: 100,"))
        #expect(!content.contains("fit-content"))
    }

    @Test("fit_content(N) on a frame whose only child is absolute is N")
    func fitFallbackWithOnlyAbsoluteChild() throws {
        let content = try emitBox("""
        "width": "fit_content(120)", "height": 50,
        "children": [{"type": "rectangle", "id": "R1", "layoutPosition": "absolute", "x": 0, "y": 0,
                      "width": 40, "height": 40}]
        """)
        #expect(content.contains("width: 120,"))
    }

    @Test("fit_content(N) on an empty frame with padding along that side fits the padding")
    func fitFallbackYieldsToPadding() throws {
        let content = try emitBox(#""width": "fit_content(200)", "height": "fit_content(100)", "padding": [0, 12]"#)
        #expect(content.contains(#"width: "fit-content","#))
        #expect(content.contains("height: 100,"))
    }

    @Test("fit_content(N) on a rectangle is N")
    func fitFallbackOnRectangle() throws {
        let content = try emitBox("""
        "width": 300, "height": 300,
        "children": [{"type": "rectangle", "id": "R1", "width": "fit_content(30)", "height": 20, "fill": "#FF0000"}]
        """)
        #expect(content.contains("width: 30,"))
    }

    // MARK: - fill_container fallbacks

    @Test("fill_container(N) under a layout-none frame is N")
    func fillFallbackUnderLayoutNone() throws {
        let content = try emitBox("""
        "layout": "none", "width": 300, "height": 200,
        "children": [{"type": "rectangle", "id": "R1", "x": 0, "y": 0, "fill": "#FF0000",
                      "width": "fill_container(150)", "height": "fill_container(80)"}]
        """)
        #expect(content.contains("width: 150,"))
        #expect(content.contains("height: 80,"))
        #expect(!content.contains(#""100%""#))
    }

    @Test("fill_container(N) on a frame inside a group is N")
    func fillFallbackUnderGroup() throws {
        let content = try emitBox("""
        "layout": "none", "width": 300, "height": 200,
        "children": [{"type": "group", "id": "G1", "x": 0, "y": 0, "children": [
          {"type": "frame", "id": "F1", "x": 0, "y": 0, "fill": "#FF0000",
           "width": "fill_container(150)", "height": 20}]}]
        """)
        #expect(content.contains("width: 150,"))
    }

    @Test("fill_container(N) on an absolute child of a flex frame is N")
    func fillFallbackOnAbsoluteChild() throws {
        let content = try emitBox("""
        "width": 300, "height": 200,
        "children": [{"type": "rectangle", "id": "R1", "layoutPosition": "absolute", "x": 0, "y": 0,
                      "fill": "#FF0000", "width": "fill_container(150)", "height": 20}]
        """)
        #expect(content.contains("width: 150,"))
    }

    // MARK: - layout: none

    @Test("A layout-none frame with no size settles at 0 × 0, whatever its children")
    func layoutNoneFrameWithoutSizeIsZero() throws {
        let content = try emitBox("""
        "width": 300, "height": 300,
        "children": [{"type": "frame", "id": "N1", "layout": "none", "fill": "#00FF00",
          "children": [{"type": "rectangle", "id": "R1", "x": 10, "y": 10, "width": 40, "height": 40}]}]
        """)
        #expect(content.contains("width: 0,"))
        #expect(content.contains("height: 0,"))
    }

    @Test("A layout-none frame sized fit_content(N) is N, not its children's union")
    func layoutNoneFrameFitIsItsFallback() throws {
        let content = try emitBox("""
        "width": 300, "height": 300,
        "children": [{"type": "frame", "id": "N1", "layout": "none", "fill": "#00FF00",
          "width": "fit_content(70)", "height": "fit_content",
          "children": [{"type": "rectangle", "id": "R1", "x": 10, "y": 10, "width": 140, "height": 140}]}]
        """)
        #expect(content.contains("width: 70,"))
        #expect(content.contains("height: 0,"))
        #expect(!content.contains("fit-content"))
    }

    // MARK: - Cross axis

    @Test("A frame with no height in a row keeps its content height rather than stretching")
    func unsizedHeightInRowFitsContent() throws {
        let content = try emitBox("""
        "width": 300, "height": 100,
        "children": [{"type": "frame", "id": "C1", "layout": "vertical", "width": 50, "fill": "#00FF00",
          "children": [{"type": "rectangle", "id": "R1", "width": 40, "height": 20}]}]
        """)
        #expect(content.contains(#"height: "fit-content","#))
    }

    @Test("A frame with no width in a column keeps its content width rather than stretching")
    func unsizedWidthInColumnFitsContent() throws {
        let content = try emitBox("""
        "layout": "vertical", "width": 300, "height": 100,
        "children": [{"type": "frame", "id": "C1", "height": 50, "fill": "#00FF00",
          "children": [{"type": "rectangle", "id": "R1", "width": 40, "height": 20}]}]
        """)
        #expect(content.contains(#"width: "fit-content","#))
    }
}
