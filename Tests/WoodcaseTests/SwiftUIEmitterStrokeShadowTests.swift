//
//  SwiftUIEmitterStrokeShadowTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a stroked node's outer shadow is cast by in emitted SwiftUI: Pen casts it from the
/// node's silhouette, its shape grown by the part of the stroke band outside it — outside
/// and centred strokes, per side, on every shape kind — never from a line, and knocks it out
/// under the whole silhouette. ``SwiftUIRenderTests`` measures the same against Pen's exports
/// of `render-stroke-shadows` and `render-sizeless-frames`.
struct SwiftUIEmitterStrokeShadowTests {
    private static let shadow = ##""effect": {"type": "shadow", "color": "#000000", "blur": 4}"##

    @Test("An outside stroke casts with its shape: the band united with the outline")
    func outsideStroke() throws {
        let code = try body(child: rect(##""stroke": "#00FF00", "strokeWidth": 12, "strokeAlignment": "outer""##))
        #expect(code.contains(
            ".penDropShadow(PenSilhouette(Rectangle(), stroke: Rectangle().penStroke(.outside, lineWidth: 12)), color: Color(hex: 0x000000), radius: 2)"
        ))
    }

    @Test("A centred stroke casts with its shape, as does one with no alignment")
    func centredStroke() throws {
        let centred = try body(child: rect(##""stroke": "#00FF00", "strokeWidth": 6, "strokeAlignment": "center""##))
        #expect(centred.contains(".penDropShadow(PenSilhouette(Rectangle(), stroke: Rectangle().penStroke(.center, lineWidth: 6)), "))
        let unset = try body(child: rect(##""stroke": "#00FF00""##))
        #expect(unset.contains(".penDropShadow(PenSilhouette(Rectangle(), stroke: Rectangle().penStroke(.center, lineWidth: 1)), "))
    }

    @Test("An inside stroke lies within the shape, so the shape alone casts")
    func insideStroke() throws {
        let code = try body(child: rect(##""stroke": "#00FF00", "strokeWidth": 12, "strokeAlignment": "inner""##))
        #expect(code.contains(".penDropShadow(Rectangle(), color: Color(hex: 0x000000), radius: 2)"))
        #expect(!code.contains("PenSilhouette"))
    }

    @Test("A stroke with no paint, or no width, casts nothing of its own")
    func unpaintedStroke() throws {
        let zero = try body(child: rect(##""stroke": "#00FF00", "strokeWidth": 0, "strokeAlignment": "outer""##))
        #expect(zero.contains(".penDropShadow(Rectangle(), "))
        let none = try body(child: rect(##""strokeWidth": 8, "strokeAlignment": "outer""##))
        #expect(none.contains(".penDropShadow(Rectangle(), "))
    }

    @Test("Caps and joins shape the band the silhouette takes")
    func capsAndJoins() throws {
        let code = try body(child: rect(##""cornerRadius": 8, "stroke": "#00FF00", "strokeWidth": 4, "strokeLinejoin": "round""##))
        #expect(code.contains(
            "PenSilhouette(RoundedRectangle(cornerRadius: 8, style: .circular), stroke: RoundedRectangle(cornerRadius: 8, style: .circular).penStroke(.center, style: StrokeStyle(lineWidth: 4, lineJoin: .round)))"
        ))
    }

    @Test("A width per side casts the per-side band")
    func perSideStroke() throws {
        let frame = ##"{"type": "frame", "id": "f", "width": 40, "height": 30, "fill": "#808080", "stroke": "#00FF00", "strokeWidth": {"top": 4, "right": 16, "bottom": 8, "left": 0}, "strokeAlignment": "outer", \##(Self.shadow)}"##
        let code = try body(child: frame)
        #expect(code.contains(
            ".penDropShadow(PenSilhouette(Rectangle(), stroke: PenSideStroke(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 16), alignment: .outside)), "
        ))
    }

    @Test("A frame with children casts its box and its stroke band, not its children")
    func frameWithChildren() throws {
        let child = ##"{"type": "rectangle", "id": "c", "width": 5, "height": 5, "fill": "#FF00FF"}"##
        let frame = ##"{"type": "frame", "id": "f", "width": 40, "height": 30, "layout": "none", "stroke": "#00FF00", "strokeWidth": 6, "strokeAlignment": "outer", \##(Self.shadow), "children": [\##(child)]}"##
        let code = try body(child: frame)
        #expect(code.contains(".penDropShadow(PenSilhouette(Rectangle(), stroke: Rectangle().penStroke(.outside, lineWidth: 6)), "))
    }

    @Test("A 0×0 frame casts the band laid out from its box, drawn in a box the stroke's reach larger")
    func pointFrame() throws {
        let child = ##"{"type": "rectangle", "id": "c", "x": 10, "y": 10, "width": 80, "height": 40, "fill": "#FF00FF"}"##
        let frame = ##"{"type": "frame", "id": "f", "x": 50, "y": 50, "layout": "none", "fill": "#808080", "stroke": "#00FF00", "strokeWidth": 8, "strokeAlignment": "outer", \##(Self.shadow), "children": [\##(child)]}"##
        let code = try body(child: frame, layout: "none")
        #expect(code.contains(
            ".penDropShadow(PenSilhouette(Rectangle(), stroke: PenSideStroke(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), alignment: .outside)), color: Color(hex: 0x000000), radius: 2, outset: CGSize(width: 8, height: 8))"
        ))
    }

    @Test("An ellipse, a polygon and a path cast their outline and their band")
    func otherShapes() throws {
        let ellipse = try body(child: ##"{"type": "ellipse", "id": "e", "width": 30, "height": 20, "stroke": "#00FF00", "strokeWidth": 4, "strokeAlignment": "outer", \##(Self.shadow)}"##)
        #expect(ellipse.contains(".penDropShadow(PenSilhouette(Ellipse(), stroke: Ellipse().penStroke(.outside, lineWidth: 4)), "))
        let polygon = try body(child: ##"{"type": "polygon", "id": "p", "name": "Star", "width": 30, "height": 20, "polygonCount": 5, "stroke": "#00FF00", "strokeWidth": 4, "strokeAlignment": "outer", \##(Self.shadow)}"##)
        #expect(polygon.contains(".penDropShadow(PenSilhouette(StarShape(), stroke: StarShape().penStroke(.outside, lineWidth: 4)), "))
        let path = try body(child: ##"{"type": "path", "id": "h", "name": "Tri", "width": 30, "height": 20, "geometry": "M0 0 L30 0 L15 20 Z", "stroke": "#00FF00", "strokeWidth": 4, \##(Self.shadow)}"##)
        #expect(path.contains(".penDropShadow(PenSilhouette(TriShape(), stroke: TriShape().penStroke(.center, lineWidth: 4)), "))
    }

    @Test("An even-odd shape unites with its band by the even-odd rule")
    func evenOddShape() throws {
        let geometry = "M0 0 L30 0 L30 20 L0 20 Z M10 5 L20 5 L20 15 L10 15 Z"
        let code = try body(child: ##"{"type": "path", "id": "h", "name": "Ring", "width": 30, "height": 20, "geometry": "\##(geometry)", "fillRule": "evenodd", "fill": "#808080", "stroke": "#00FF00", "strokeWidth": 2, \##(Self.shadow)}"##)
        #expect(code.contains(".penDropShadow(PenSilhouette(RingShape(), stroke: RingShape().penStroke(.center, lineWidth: 2), eoFill: true), "))
    }

    @Test("An even-odd shape with no stroke casts an even-odd shadow")
    func evenOddShapeNoStroke() throws {
        let geometry = "M0 0 L30 0 L30 20 L0 20 Z M10 5 L20 5 L20 15 L10 15 Z"
        let code = try body(child: ##"{"type": "path", "id": "h", "name": "Ring", "width": 30, "height": 20, "geometry": "\##(geometry)", "fillRule": "evenodd", "fill": "#808080", \##(Self.shadow)}"##)
        #expect(code.contains(".penDropShadow(RingShape(), color: Color(hex: 0x000000), radius: 2, eoFill: true)"))
    }

    @Test("A line casts no shadow from its stroke, as Pen casts none")
    func lineCastsNothing() throws {
        let code = try body(child: ##"{"type": "line", "id": "l", "name": "Rule", "width": 30, "height": 20, "stroke": "#00FF00", "strokeWidth": 4, \##(Self.shadow)}"##)
        #expect(!code.contains("PenSilhouette"))
    }

    // MARK: - Helpers

    private func rect(_ keys: String) -> String {
        ##"{"type": "rectangle", "id": "r", "width": 40, "height": 30, "fill": "#808080", \##(Self.shadow), \##(keys)}"##
    }

    /// Emit a 2.19 document whose root frame, of `layout`, holds `child`, and return the page's source.
    private func body(child: String, layout: String = "horizontal") throws -> String {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "width": 200, "height": 200, "layout": "\##(layout)", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
