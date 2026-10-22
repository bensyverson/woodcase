//
//  SwiftUIEmitterPaintIsolationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How emitted SwiftUI keeps a paint's blend mode within its node: a paint blends only with
/// the paints beneath it on the node — fills, then strokes — and never with what lies behind
/// the node (Ben's reading-1 ruling, 2026-10-20; `PenPaintStack`). The lowest paint has
/// nothing beneath it, so its blend is left out; a stack that still blends is composited as
/// a group of its own. ``SwiftUIPaintBlendRenderTests`` measures the renders against CG.
struct SwiftUIEmitterPaintIsolationTests {
    @Test("A lone blended fill blends with nothing: it is written without its blend mode")
    func loneFill() throws {
        let code = try body(child: rect(fill: ##"{"type": "color", "color": "#0000FF", "blendMode": "multiply"}"##))
        #expect(code.contains(".fill(Color(hex: 0x0000FF))"))
        #expect(!code.contains(".blendMode("))
        #expect(!code.contains(".compositingGroup()"))
    }

    @Test("A blended fill over an opaque color needs no group: the color covers the backdrop")
    func overOpaqueFill() throws {
        let code = try body(child: rect(fill: ##"["#FFFF00", {"type": "color", "color": "#0000FF", "blendMode": "multiply"}]"##))
        #expect(code.contains(".fill(Color(hex: 0x0000FF).blendMode(.multiply))"))
        #expect(!code.contains(".compositingGroup()"))
    }

    @Test("A blended fill over a translucent one composites the node's paints as a group")
    func overTranslucentFill() throws {
        let code = try body(child: rect(fill: ##"["#E6994D66", {"type": "color", "color": "#3366FF", "blendMode": "softLight"}]"##))
        let blend = try #require(code.range(of: ".blendMode(.softLight)"))
        let group = try #require(code.range(of: ".compositingGroup()"))
        #expect(blend.upperBound <= group.lowerBound)
    }

    @Test("A blended stroke over a fill groups the fill and the stroke together")
    func strokeOverFill() throws {
        let child = ##"{"type": "rectangle", "id": "r", "width": 60, "height": 60, "fill": "#FFFF00", "stroke": {"type": "color", "color": "#0000FF", "blendMode": "multiply"}, "strokeWidth": 12, "strokeAlignment": "center"}"##
        let code = try body(child: child)
        let stroke = try #require(code.range(of: ".blendMode(.multiply)"))
        let group = try #require(code.range(of: ".compositingGroup()"))
        #expect(stroke.upperBound <= group.lowerBound)
    }

    @Test("A lone blended stroke paint with no fill beneath it blends with nothing")
    func loneStroke() throws {
        let child = ##"{"type": "rectangle", "id": "r", "width": 60, "height": 60, "stroke": {"type": "color", "color": "#0000FF", "blendMode": "multiply"}, "strokeWidth": 4}"##
        let code = try body(child: child)
        #expect(!code.contains(".blendMode("))
        #expect(!code.contains(".compositingGroup()"))
    }

    @Test("A frame with children groups its own blended paints in one background, not its children")
    func frameWithChildren() throws {
        let frame = ##""width": 120, "height": 120, "fill": ["#E6994D66", {"type": "color", "color": "#3366FF", "blendMode": "softLight"}], "##
        let child = ##"{"type": "rectangle", "id": "c", "width": 20, "height": 20, "fill": "#00FF00", "blendMode": "multiply"}"##
        let code = try body(child: child, frame: frame)
        // The paints are one background whose stack is the group.
        let background = try #require(code.range(of: ".background {"))
        let group = try #require(code.range(of: ".compositingGroup()"))
        #expect(background.upperBound <= group.lowerBound)
        #expect(code.components(separatedBy: ".compositingGroup()").count == 2)
        // The child's own blend still reaches through the frame: the group closes before the
        // frame's background ends, and the child sits above it, ungrouped.
        let childBlend = try #require(code.range(of: ".blendMode(.multiply)"))
        #expect(childBlend.upperBound <= background.lowerBound)
    }

    @Test("A lone blended text paint is the text's plain foreground style")
    func loneTextPaint() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "fill": {"type": "color", "color": "#0000FF", "blendMode": "multiply"}}"##
        let code = try body(child: text)
        #expect(code.contains(".foregroundStyle(Color(hex: 0x0000FF))"))
        #expect(!code.contains(".blendMode("))
    }

    @Test("A text's blended paint stack over a translucent paint is composited as a group")
    func textStack() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "fill": ["#E6994D66", {"type": "color", "color": "#3366FF", "blendMode": "softLight"}]}"##
        let code = try body(child: text)
        let fill = try #require(code.range(of: ".penTextFill {"))
        let group = try #require(code.range(of: ".compositingGroup()"))
        #expect(fill.upperBound <= group.lowerBound)
    }

    // MARK: - Helpers

    private func rect(fill: String) -> String {
        ##"{"type": "rectangle", "id": "r", "width": 60, "height": 60, "fill": \##(fill)}"##
    }

    private func body(child: String, frame keys: String = "") throws -> String {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "root", "name": "Board", \##(keys)"children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
