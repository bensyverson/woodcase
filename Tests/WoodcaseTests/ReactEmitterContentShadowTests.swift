//
//  ReactEmitterContentShadowTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter casts a box node's outer shadows from what it paints, as pen CLI
/// 0.3.13 and the CG renderer do (``PenShadowSilhouette``): a `box-shadow` where the
/// silhouette is the box, a `drop-shadow()` of the element's content everywhere else
/// (leaf `S1cB6z`; `render-content-shadows.pen`).
struct ReactEmitterContentShadowTests {
    // MARK: - Helpers

    /// The emitted `Card` component, whose one child is `child` (a JSON object).
    private func card(_ child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.19",
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

    /// One black outer shadow, `10 14` with blur 4.
    private static let shadow = ##"{"type": "shadow", "shadowType": "outer", "color": "#000000FF", "offset": {"x": 10, "y": 14}, "blur": 4}"##

    /// That shadow as a `drop-shadow()`: its blur length is half Pen's.
    private static let dropShadow = ##"filter: "drop-shadow(10px 14px 2px #000000FF)","##

    /// That shadow as a `box-shadow`, its opaque black written `#010101`, which WebKit draws
    /// (``ReactEmitterBoxShadowWorkaroundTests``).
    private static let boxShadow = ##"boxShadow: "10px 14px 4px #010101","##

    /// Two children of a 100×100 frame, the ellipse reaching past its box.
    private static let children = ##"""
    [{"type": "rectangle", "id": "Ca", "x": 10, "y": 10, "width": 40, "height": 40, "fill": "#CC6600"},
     {"type": "ellipse", "id": "Cb", "x": 70, "y": 70, "width": 50, "height": 50, "fill": "#2288FF"}]
    """##

    /// A 100×100 `layout: none` frame casting ``shadow``, with `extra` keys.
    private func frame(_ extra: String) -> String {
        ##"{"type": "frame", "id": "F1", "name": "Holder", "width": 100, "height": 100, "layout": "none", "effect": \##(Self.shadow)\##(extra)}"##
    }

    // MARK: - Frames

    @Test("A fill-less frame casts its children's shadow: a drop-shadow of its content, not a box-shadow")
    func fillLessFrameCastsContent() throws {
        let content = try card(frame(##", "children": \##(Self.children)"##))
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("boxShadow"))
    }

    @Test("A filled frame whose children reach past its unclipped box casts them too")
    func filledOverhangCastsContent() throws {
        let content = try card(frame(##", "fill": "#DDDDDD", "children": \##(Self.children)"##))
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("boxShadow"))
    }

    @Test("A translucent frame whose children reach past it keeps its box-shadow: a drop-shadow would cast its fill faint and show through it")
    func translucentOverhangCastsBox() throws {
        let content = try card(frame(##", "fill": "#DDDDDD40", "children": \##(Self.children)"##))
        #expect(content.contains(Self.boxShadow))
        #expect(!content.contains("drop-shadow"))
    }

    @Test("A frame filled with a theme color whose children reach past it casts from its content, the color taken as opaque")
    func themedOverhangCastsContent() throws {
        let content = try card(frame(##", "fill": "$surface", "children": \##(Self.children)"##))
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("boxShadow"))
    }

    @Test("A filled frame whose children flow inside it keeps its box-shadow")
    func filledFlowCastsBox() throws {
        let child = ##"""
        {"type": "frame", "id": "F1", "name": "Holder", "width": 100, "height": 100, "layout": "vertical", "fill": "$surface",
         "effect": \##(Self.shadow), "children": [{"type": "rectangle", "id": "Ca", "width": 40, "height": 40, "fill": "#CC6600"}]}
        """##
        let content = try card(child)
        #expect(content.contains(##"boxShadow: "10px 14px 4px #010101","##))
        #expect(!content.contains("drop-shadow"))
    }

    @Test("A filled free frame whose children sit inside its box keeps its box-shadow")
    func filledContainedCastsBox() throws {
        let inside = ##"[{"type": "rectangle", "id": "Ca", "x": 10, "y": 10, "width": 40, "height": 40, "fill": "#CC6600"}]"##
        let content = try card(frame(##", "fill": "#DDDDDD", "children": \##(inside)"##))
        #expect(content.contains(Self.boxShadow))
        #expect(!content.contains("drop-shadow"))
    }

    @Test("A child whose outer stroke reaches past the box overhangs it")
    func strokeOverhangCastsContent() throws {
        let stroked = ##"[{"type": "rectangle", "id": "Ca", "x": 0, "y": 0, "width": 40, "height": 40, "fill": "#CC6600", "stroke": "#000000", "strokeWidth": 4, "strokeAlignment": "outer"}]"##
        let content = try card(frame(##", "fill": "#DDDDDD", "children": \##(stroked)"##))
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("10px 14px 4px"))
    }

    @Test("A filled frame that clips its children casts its box: a box-shadow")
    func filledClippedCastsBox() throws {
        let content = try card(frame(##", "fill": "#DDDDDD", "clip": true, "children": \##(Self.children)"##))
        #expect(content.contains(Self.boxShadow))
        #expect(!content.contains("drop-shadow"))
    }

    @Test("A filled frame with no children casts its box")
    func filledChildlessCastsBox() throws {
        let content = try card(frame(##", "fill": "#DDDDDD""##))
        #expect(content.contains(Self.boxShadow))
        #expect(!content.contains("drop-shadow"))
    }

    @Test("A frame whose fill is disabled or transparent casts from its content", arguments: [
        ##", "fill": {"type": "color", "color": "#DDDDDD", "enabled": false}, "clip": true"##,
        ##", "fill": "#DDDDDD00", "clip": true"##,
    ])
    func invisibleFillCastsContent(fill: String) throws {
        let content = try card(frame(fill + ##", "children": \##(Self.children)"##))
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("boxShadow"))
    }

    @Test("A fill-less stroked frame casts its stroke's ring, not its box: the stroke stays a box-shadow, the shadow a drop-shadow")
    func strokeOnlyFrameCastsRing() throws {
        let content = try card(frame(##", "stroke": "#333333", "strokeWidth": 8"##))
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("10px 14px 4px"))
    }

    @Test("A frame casting from content keeps its inner shadow an inset box-shadow")
    func contentCastKeepsInnerShadow() throws {
        let effects = ##"[\##(Self.shadow), {"type": "shadow", "shadowType": "inner", "color": "#FF0000", "offset": {"x": 2, "y": 2}, "blur": 3}]"##
        let child = ##"{"type": "frame", "id": "F1", "name": "Holder", "width": 100, "height": 100, "layout": "none", "effect": \##(effects), "children": \##(Self.children)}"##
        let content = try card(child)
        #expect(content.contains(##"boxShadow: "inset 2px 2px 3px #FF0000","##))
        #expect(content.contains(Self.dropShadow))
    }

    @Test("A frame's content shadows and its layer blur share one filter, the blur after the shadows")
    func contentShadowAndBlurShareOneFilter() throws {
        let effects = ##"[{"type": "blur", "radius": 4}, \##(Self.shadow)]"##
        let child = ##"{"type": "frame", "id": "F1", "name": "Holder", "width": 100, "height": 100, "layout": "none", "effect": \##(effects), "children": \##(Self.children)}"##
        let content = try card(child)
        #expect(content.contains(##"filter: "drop-shadow(10px 14px 2px #000000FF) blur(2px)","##))
        #expect(content.components(separatedBy: "filter:").count == 2)
    }

    @Test("A blended shadow cast from a frame's content is drawn unblended, with a warning, not layered")
    func blendedContentShadowWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        let blended = ##"{"type": "shadow", "shadowType": "outer", "color": "#FF0000", "offset": {"x": 2, "y": 2}, "blur": 4, "blendMode": "multiply"}"##
        let child = ##"{"type": "frame", "id": "F1", "name": "Holder", "width": 100, "height": 100, "layout": "none", "effect": \##(blended), "children": \##(Self.children)}"##
        let content = try card(child, diagnostics: diagnostics)
        #expect(content.contains(##"filter: "drop-shadow(2px 2px 2px #FF0000)","##))
        #expect(!content.contains("aria-hidden"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "F1" && $0.message.contains("blend") })
    }

    // MARK: - Rectangles and ellipses

    @Test("A rectangle with a transparent fill and no stroke casts nothing: a drop-shadow of its empty content")
    func transparentRectangleCastsContent() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "width": 100, "height": 100, "fill": "#DDDDDD00", "effect": \##(Self.shadow)}"##)
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("10px 14px 4px"))
    }

    @Test("A fill-less stroked rectangle casts its ring through a drop-shadow")
    func strokeOnlyRectangleCastsRing() throws {
        let content = try card(##"{"type": "rectangle", "id": "R1", "width": 100, "height": 100, "stroke": "#333333", "strokeWidth": 8, "effect": \##(Self.shadow)}"##)
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("10px 14px 4px"))
    }

    @Test("A fill-less stroked ellipse drawn as a box casts its ring through a drop-shadow")
    func strokeOnlyEllipseCastsRing() throws {
        let content = try card(##"{"type": "ellipse", "id": "E1", "width": 100, "height": 100, "stroke": "#333333", "strokeWidth": 8, "effect": \##(Self.shadow)}"##)
        #expect(content.contains(Self.dropShadow))
        #expect(!content.contains("10px 14px 4px"))
    }

    @Test("A filled ellipse drawn as a box keeps its box-shadow")
    func filledEllipseCastsBox() throws {
        let content = try card(##"{"type": "ellipse", "id": "E1", "width": 100, "height": 100, "fill": "#2288FF", "effect": \##(Self.shadow)}"##)
        #expect(content.contains(Self.boxShadow))
        #expect(!content.contains("drop-shadow"))
    }
}
