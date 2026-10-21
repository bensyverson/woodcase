//
//  ReactEmitterPaintBlendTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter writes a paint's blend mode under Ben's reading-1 ruling
/// (2026-10-20): a paint blends only within its node's own paints, fills then strokes, as
/// one isolated group — CSS's `background-blend-mode` model — and only the node's own blend
/// mode reaches the backdrop, as `mix-blend-mode`.
///
/// So a lone blended fill blends with nothing and is written without a blend; a stack keeps
/// `background-blend-mode`; and a paint drawn by an element of its own (a stroke overlay, a
/// fill layer, an SVG shape copy) keeps its `mix-blend-mode`, inside a host that isolates.
struct ReactEmitterPaintBlendTests {
    /// The emitted `Card` component: a frame holding `child`, given as JSON.
    private func card(child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.20",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document),
            diagnostics: diagnostics
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    private static let blueMultiply = ##"{"type": "color", "color": "#0000FF", "blendMode": "multiply"}"##

    // MARK: - A lone blended paint blends with nothing

    @Test("A rectangle's lone blended fill is written without a blend, and its parent does not isolate")
    func loneFill() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60, "fill": \(Self.blueMultiply)}
        """)
        #expect(content.contains(##"backgroundColor: "#0000FF""##), "\(content)")
        #expect(!content.contains("mixBlendMode"), "\(content)")
        // The card's own element, up to its child's: no isolation there.
        let card = try #require(content.range(of: "<div"))
        let child = try #require(content.range(of: "<div", range: card.upperBound ..< content.endIndex))
        #expect(!content[..<child.lowerBound].contains("isolation"), "\(content)")
    }

    @Test("A frame's lone blended gradient is written without a blend, so its children do not blend")
    func loneFrameGradient() throws {
        let content = try card(child: """
        {"type": "frame", "id": "F1", "width": 60, "height": 60,
         "fill": {"type": "gradient", "gradientType": "linear", "blendMode": "screen",
                  "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]},
         "children": [{"type": "rectangle", "id": "K1", "width": 10, "height": 10, "fill": "#FFFFFF"}]}
        """)
        #expect(!content.contains("mixBlendMode"), "\(content)")
    }

    @Test("A text's lone blended color is written without a blend")
    func loneTextColor() throws {
        let content = try card(child: """
        {"type": "text", "id": "T1", "content": "Hi", "fill": \(Self.blueMultiply)}
        """)
        #expect(content.contains(##"color: "#0000FF""##), "\(content)")
        #expect(!content.contains("mixBlendMode"), "\(content)")
    }

    @Test("A node's own blend still blends the element, whatever its paint's")
    func nodeBlendStays() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60,
         "fill": {"type": "color", "color": "#0000FF", "blendMode": "screen"},
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "multiply"}}}
        """)
        #expect(content.contains(##"mixBlendMode: "multiply""##), "\(content)")
        #expect(!content.contains(##"mixBlendMode: "screen""##), "\(content)")
    }

    // MARK: - A paint on an element of its own blends inside an isolated host

    @Test("A blended stroke overlay blends with the node's fills inside a host that isolates")
    func strokeOverlayIsolates() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60, "fill": "#FFFF00",
         "stroke": \(Self.blueMultiply), "strokeWidth": 8}
        """)
        #expect(content.contains(##"mixBlendMode: "multiply""##), "\(content)")
        #expect(content.contains(##"isolation: "isolate""##), "\(content)")
    }

    @Test("An SVG shape whose fills blend isolates its svg element")
    func svgFillsIsolate() throws {
        let content = try card(child: """
        {"type": "path", "id": "P1", "width": 100, "height": 100, "geometry": "M0 0 L100 0 L100 100 Z",
         "fill": ["#FFFF00", \(Self.blueMultiply)]}
        """)
        #expect(content.contains(##"mixBlendMode: "multiply""##), "\(content)")
        #expect(content.contains(##"isolation: "isolate""##), "\(content)")
    }

    @Test("An SVG shape's lone blended fill is written without a blend")
    func svgLoneFill() throws {
        let content = try card(child: """
        {"type": "path", "id": "P1", "width": 100, "height": 100, "geometry": "M0 0 L100 0 L100 100 Z",
         "fill": \(Self.blueMultiply)}
        """)
        #expect(!content.contains("mixBlendMode"), "\(content)")
    }

    // MARK: - What CSS cannot say

    /// The overlay's layers blend among themselves by `background-blend-mode`, which never
    /// reaches the node's fills beneath, so the lowest stroke layer's blend is lost.
    @Test("A stacked stroke whose lowest layer blends over fills warns that CSS cannot blend it with them")
    func stackedStrokeOverFillsWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        _ = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60, "fill": "#FFFF00",
         "stroke": [\(Self.blueMultiply), "#FF000080"], "strokeWidth": 8}
        """, diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "R1" && $0.message.contains("blend") })
    }

    @Test("A stacked stroke whose lowest layer blends over no fill draws exactly, without a warning")
    func stackedStrokeAloneIsExact() throws {
        let diagnostics = PenDiagnosticCollector()
        _ = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60,
         "stroke": [\(Self.blueMultiply), "#FF000080"], "strokeWidth": 8}
        """, diagnostics: diagnostics)
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "R1" && $0.message.contains("blend") })
    }

    // MARK: - Linear dodge and burn (8nwlNY)

    /// CSS Compositing Level 2's `plus-lighter` is a true add, and WebKit draws it, but only
    /// as `mix-blend-mode`: `background-blend-mode` takes no plus operator, and WebKit drops
    /// the whole declaration that names one.
    @Test("A node's linear dodge is mix-blend-mode plus-lighter")
    func nodeLinearDodge() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60, "fill": "#3366FF",
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "linearDodge"}}}
        """)
        #expect(content.contains(##"mixBlendMode: "plus-lighter""##), "\(content)")
    }

    @Test("A linear dodge fill over another is a layer of its own at plus-lighter, never a background blend")
    func stackedLinearDodge() throws {
        let content = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60,
         "fill": ["#E6994D", {"type": "color", "color": "#3366FF", "blendMode": "linearDodge"}]}
        """)
        #expect(content.contains(##"mixBlendMode: "plus-lighter""##), "\(content)")
        #expect(!content.contains("backgroundBlendMode"), "\(content)")
        #expect(content.contains(##"isolation: "isolate""##), "\(content)")
    }

    @Test("A linear dodge in a text's paint stack stays color-dodge, with a warning")
    func textLinearDodgeWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        let content = try card(child: """
        {"type": "text", "id": "T1", "content": "Hi",
         "fill": ["#E6994D", {"type": "color", "color": "#3366FF", "blendMode": "linearDodge"}]}
        """, diagnostics: diagnostics)
        #expect(content.contains(##"backgroundBlendMode: "color-dodge, normal""##), "\(content)")
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "T1" && $0.message.contains("linear dodge") })
    }

    @Test("Linear burn stays color-burn, with a warning that CSS has none")
    func linearBurnWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        let content = try card(child: """
        {"type": "rectangle", "id": "R1", "width": 60, "height": 60, "fill": "#3366FF",
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "linearBurn"}}}
        """, diagnostics: diagnostics)
        #expect(content.contains(##"mixBlendMode: "color-burn""##), "\(content)")
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "R1" && $0.message.contains("linear burn") })
    }
}
