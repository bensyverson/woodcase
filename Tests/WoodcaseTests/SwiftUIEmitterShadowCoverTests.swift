//
//  SwiftUIEmitterShadowCoverTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// When a frame's own fill covers everything its children cast, so its outer shadow is cast
/// by its own silhouette (`.penDropShadow`) rather than an inked copy of its content
/// (`.penContentShadows`): a fill that paints, and every descendant's painted extent, under
/// every theme, inside the frame's shape and clear of its rounded corners. Anything the
/// emitter cannot bound — a turned child, a frame with no painting fill — keeps the copy.
struct SwiftUIEmitterShadowCoverTests {
    private static let shadow = ##""effect": {"type": "shadow", "color": "#000000", "blur": 4}"##

    @Test("A filled, unclipped frame whose children sit inside it casts its own silhouette alone")
    func childrenInside() throws {
        let code = try body(frame(children: [rect(x: 10, y: 10, width: 30, height: 20)]))
        #expect(code.contains(".penDropShadow(Rectangle(), color: Color(hex: 0x000000), radius: 2)"))
        #expect(!code.contains("penContentShadows"))
    }

    @Test("A child that overhangs the frame casts with it, through the inked copy")
    func childOverhangs() throws {
        let code = try body(frame(children: [rect(x: 80, y: 10, width: 40, height: 20)]))
        #expect(code.contains(".penContentShadows("))
        #expect(!code.contains(".penDropShadow("))
    }

    @Test("A child in a rounded corner is not covered by the frame's shape; one clear of the corners is")
    func roundedCorners() throws {
        let corner = try body(frame(keys: ##""cornerRadius": 20"##, children: [rect(x: 2, y: 2, width: 10, height: 10)]))
        #expect(corner.contains(".penContentShadows("))
        let middle = try body(frame(keys: ##""cornerRadius": 20"##, children: [rect(x: 40, y: 30, width: 20, height: 20)]))
        #expect(middle.contains(".penDropShadow(RoundedRectangle(cornerRadius: 20, style: .circular), "))
        #expect(!middle.contains("penContentShadows"))
    }

    @Test("A frame whose fill paints nothing covers nothing, so its children cast through the copy")
    func transparentFill() throws {
        let code = try body(frame(fill: "#80808000", children: [rect(x: 10, y: 10, width: 30, height: 20)]))
        #expect(code.contains(".penContentShadows("))
    }

    @Test("A child's outer stroke that reaches past the frame is not covered")
    func strokeReach() throws {
        let stroked = ##"{"type": "rectangle", "id": "c", "x": 2, "y": 30, "width": 30, "height": 20, "fill": "#FF00FF", "stroke": "#00FF00", "strokeWidth": 8, "strokeAlignment": "outer"}"##
        let code = try body(frame(children: [stroked]))
        #expect(code.contains(".penContentShadows("))
    }

    @Test("A turned child is never counted as covered")
    func turnedChild() throws {
        let turned = ##"{"type": "rectangle", "id": "c", "x": 40, "y": 30, "width": 10, "height": 10, "rotation": 30, "fill": "#FF00FF"}"##
        let code = try body(frame(children: [turned]))
        #expect(code.contains(".penContentShadows("))
    }

    @Test("A child that overhangs under one theme only is not covered")
    func themedSize() throws {
        let child = ##"{"type": "rectangle", "id": "c", "x": 10, "y": 10, "width": "$w", "height": 20, "fill": "#FF00FF"}"##
        let variables = ##""themes": {"mode": ["light", "dark"]}, "variables": {"w": {"type": "number", "value": [{"value": 20}, {"value": 200, "theme": {"mode": "dark"}}]}}"##
        let code = try body(frame(children: [child]), documentKeys: variables)
        #expect(code.contains(".penContentShadows("))
    }

    // MARK: - Helpers

    private func rect(x: Double, y: Double, width: Double, height: Double) -> String {
        ##"{"type": "rectangle", "id": "c", "x": \##(x), "y": \##(y), "width": \##(width), "height": \##(height), "fill": "#FF00FF"}"##
    }

    private func frame(fill: String = "#808080", keys: String = "", children: [String]) -> String {
        let extra = keys.isEmpty ? "" : ", \(keys)"
        return ##"{"type": "frame", "id": "f", "x": 20, "y": 20, "width": 100, "height": 80, "layout": "none", "fill": "\##(fill)", \##(Self.shadow)\##(extra), "children": [\##(children.joined(separator: ", "))]}"##
    }

    /// Emit a document whose root frame holds `child` at its own `x`/`y`, and return the page's source.
    private func body(_ child: String, documentKeys: String = "") throws -> String {
        let extra = documentKeys.isEmpty ? "" : ", \(documentKeys)"
        let json = ##"{"version": "2.19"\##(extra), "children": [{"type": "frame", "id": "root", "name": "Board", "width": 200, "height": 200, "layout": "none", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
