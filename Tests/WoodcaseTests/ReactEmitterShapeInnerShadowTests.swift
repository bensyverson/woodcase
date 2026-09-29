//
//  ReactEmitterShapeInnerShadowTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// React draws the inner shadows of SVG shapes and icons with an SVG filter — the inverted
/// silhouette offset, blurred, colored and kept inside the silhouette — and warns at most
/// once per unsupported shadow (leaf 4fZZ38; `render-inner-shadow-shapes`).
struct ReactEmitterShapeInnerShadowTests {
    private static let inner = ##"{"type": "shadow", "shadowType": "inner", "color": "#000000CC", "offset": {"x": 2, "y": 2}, "blur": 4}"##
    private static let blendedInner = ##"{"type": "shadow", "shadowType": "inner", "color": "#FF0000", "offset": {"x": 0, "y": 0}, "blur": 4, "blendMode": "multiply"}"##
    private static let blendedOuter = ##"{"type": "shadow", "shadowType": "outer", "color": "#FF0000", "offset": {"x": 2, "y": 2}, "blur": 4, "blendMode": "multiply"}"##
    private static let outer = ##"{"type": "shadow", "shadowType": "outer", "color": "#00000099", "offset": {"x": 3, "y": 3}, "blur": 6}"##

    /// The `Card` component's code and every diagnostic React wrote for it.
    private func emit(_ children: [String]) throws -> (content: String, diagnostics: [PenDiagnostic]) {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(children.joined(separator: ", "))]}]}
        """)
        let collector = PenDiagnosticCollector()
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: collector
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        return (content, collector.diagnostics)
    }

    private func shadowWarnings(_ diagnostics: [PenDiagnostic]) -> [PenDiagnostic] {
        diagnostics.filter { $0.message.contains("shadow") }
    }

    private static let shapes = [
        ##"{"type": "polygon", "id": "Pol01", "width": 60, "height": 40, "polygonCount": 6, "fill": "#3B82F6", "effect": \##(inner)}"##,
        ##"{"type": "path", "id": "Pat01", "width": 60, "height": 40, "geometry": "M0 40 L30 0 L60 40 Z", "fill": "#3B82F6", "effect": \##(inner)}"##,
        ##"{"type": "ellipse", "id": "Arc01", "width": 60, "height": 40, "sweepAngle": 270, "fill": "#3B82F6", "effect": \##(inner)}"##,
        ##"{"type": "ellipse", "id": "Don01", "width": 60, "height": 40, "innerRadius": 0.5, "fill": "#3B82F6", "effect": \##(inner)}"##,
    ]

    @Test("An SVG shape's inner shadow is a filtered copy of the shape, and no warning", arguments: shapes)
    func shapeInnerShadow(shape: String) throws {
        let (content, diagnostics) = try emit([shape])
        #expect(content.contains("<filter id=\"wc-inner-"), "\(content)")
        #expect(content.contains("<feOffset dx=\"2\" dy=\"2\""), "\(content)")
        #expect(content.contains("stdDeviation=\"2\""), "\(content)")
        #expect(content.contains("filter=\"url(#wc-inner-"), "\(content)")
        #expect(shadowWarnings(diagnostics).isEmpty, "\(diagnostics)")
    }

    @Test("The shadow sits over the fill and under the stroke")
    func shadowBetweenFillAndStroke() throws {
        let (content, _) = try emit([
            ##"{"type": "polygon", "id": "Pol01", "width": 60, "height": 40, "fill": "#3B82F6", "stroke": "#FFFFFF", "strokeWidth": 4, "effect": \##(Self.inner)}"##,
        ])
        let lines = content.components(separatedBy: "\n")
        let fill = try #require(lines.firstIndex { $0.contains("<polygon") && $0.contains("fill=\"#3B82F6\"") }, "\(content)")
        let shadow = try #require(lines.firstIndex { $0.contains("filter=\"url(#wc-inner-") }, "\(content)")
        let stroke = try #require(lines.firstIndex { $0.contains("<polygon") && $0.contains("stroke=\"#FFFFFF\"") }, "\(content)")
        #expect(fill < shadow && shadow < stroke, "\(content)")
        #expect(!lines[stroke].contains("fill=\"#3B82F6\""), "the stroke carries no second fill over the shadow: \(content)")
    }

    @Test("Under a stretching viewBox the filter's lengths are in the path's own units")
    func viewBoxScalesLengths() throws {
        let (content, _) = try emit([
            ##"{"type": "path", "id": "Pat01", "width": 200, "height": 50, "viewBox": [0, 0, 100, 100], "geometry": "M0 0 L100 0 L50 100 Z", "fill": "#3B82F6", "effect": \##(Self.inner)}"##,
        ])
        #expect(content.contains("<feOffset dx=\"1\" dy=\"4\""), "\(content)")
        #expect(content.contains("stdDeviation=\"1 4\""), "\(content)")
    }

    @Test("A blended inner shadow on a shape is drawn with its blend mode, and no warning")
    func blendedShapeShadow() throws {
        let (content, diagnostics) = try emit([
            ##"{"type": "polygon", "id": "Pol01", "width": 60, "height": 40, "fill": "#FFD60A", "effect": \##(Self.blendedInner)}"##,
        ])
        let line = try #require(content.components(separatedBy: "\n").first { $0.contains("filter=\"url(#wc-inner-") }, "\(content)")
        #expect(line.contains("mixBlendMode: \"multiply\""), "\(content)")
        #expect(shadowWarnings(diagnostics).isEmpty, "\(diagnostics)")
    }

    @Test("An icon's inner shadow is a filter over its glyph, before its drop shadows, and no warning")
    func iconInnerShadow() throws {
        let (content, diagnostics) = try emit([
            ##"{"type": "icon", "id": "Ico01", "width": 48, "height": 48, "library": "lucide", "icon": "heart", "fill": "#3B82F6", "effect": [\##(Self.outer), \##(Self.inner)]}"##,
        ])
        #expect(content.contains("<filter id=\"wc-inner-"), "\(content)")
        #expect(content.contains("filter: \"url(#wc-inner-"), "\(content)")
        let filterLine = try #require(content.components(separatedBy: "\n").first { $0.contains("filter: \"url(#wc-inner-") })
        #expect(filterLine.contains(") drop-shadow("), "\(content)")
        #expect(shadowWarnings(diagnostics).isEmpty, "\(diagnostics)")
    }

    @Test("A blended inner shadow on an icon blends inside its filter, and no warning")
    func blendedIconShadow() throws {
        let (content, diagnostics) = try emit([
            ##"{"type": "icon", "id": "Ico01", "width": 48, "height": 48, "library": "lucide", "icon": "heart", "fill": "#3B82F6", "effect": \##(Self.blendedInner)}"##,
        ])
        #expect(content.contains("<feBlend in2=\"SourceGraphic\" mode=\"multiply\""), "\(content)")
        #expect(shadowWarnings(diagnostics).isEmpty, "\(diagnostics)")
    }

    // MARK: - One warning per unsupported shadow

    @Test("A blended inner shadow on text or a group is one warning, not two", arguments: [
        ##"{"type": "text", "id": "Nod01", "content": "Hi", "fill": "#000000", "effect": \##(blendedInner)}"##,
        ##"{"type": "group", "id": "Nod01", "effect": \##(blendedInner), "children": [{"type": "rectangle", "id": "Nod01r", "width": 10, "height": 10, "fill": "#FF0000"}]}"##,
    ])
    func oneWarningPerShadow(node: String) throws {
        let found = try shadowWarnings(emit([node]).diagnostics)
        #expect(found.count == 1, "\(found)")
        #expect(!found.contains { $0.message == ReactEmitter.unblendedShadowWarning }, "\(found)")
    }

    /// Green on its first run: a guard that the fix keeps the other shadow's warning.
    @Test("A blended outer shadow beside a text's inner shadow is still named")
    func blendedOuterStillWarns() throws {
        let found = try shadowWarnings(emit([
            ##"{"type": "text", "id": "Txt01", "content": "Hi", "fill": "#000000", "effect": [\##(Self.blendedOuter), \##(Self.inner)]}"##,
        ]).diagnostics)
        #expect(Set(found.map(\.message)) == [ReactEmitter.unblendedShadowWarning, ReactEmitter.textInnerShadowWarning], "\(found)")
    }
}
