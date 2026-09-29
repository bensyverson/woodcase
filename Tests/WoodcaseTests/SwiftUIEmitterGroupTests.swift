//
//  SwiftUIEmitterGroupTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a `group` becomes in emitted SwiftUI, over small synthetic documents: a box-less
/// `ZStack` whose origin is the group's anchor, with its layer effects applied to the group
/// as a whole and its shadows cast by its descendants' silhouette. ``SwiftUIRenderTests``
/// measures the same decisions against Pen's exports of `blur2`, `blur3` and
/// `render-group-shadows`.
struct SwiftUIEmitterGroupTests {
    // MARK: - Placement

    @Test("A group is a top-leading ZStack of its children, with no placeholder and no warning")
    func groupIsAStack() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(child: group(children: [rect(id: "a", x: 0, y: 0)]), diagnostics: diagnostics)
        #expect(code.contains("ZStack(alignment: .topLeading) {\n                Rectangle()"))
        #expect(!code.contains("not emitted yet"))
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "g" })
    }

    @Test("A group's children sit at their x/y from its anchor: padding, which the group's size counts")
    func childrenArePaddedFromTheAnchor() throws {
        let code = try body(child: group(children: [rect(id: "a", x: 60, y: 50)]))
        #expect(code.contains(".padding(.leading, 60)\n"))
        #expect(code.contains(".padding(.top, 50)\n"))
        #expect(!code.contains(".offset(x: 60"))
    }

    @Test("A child at a negative offset overhangs the group's anchor rather than growing it")
    func negativeChildOverhangs() throws {
        let code = try body(child: group(children: [rect(id: "a", x: -12, y: 8)]))
        #expect(code.contains(".padding(.top, 8)"))
        #expect(code.contains(".offset(x: -12)"))
    }

    @Test("A child's float-noise offset is rounded to a millionth of a point")
    func noiseIsRounded() throws {
        let code = try body(child: group(children: [rect(id: "a", x: 149.5, y: 1.2434497875801753e-14)]))
        #expect(code.contains(".padding(.leading, 149.5)"))
        #expect(!code.contains("e-14"))
    }

    @Test("The group itself is offset by its x/y in a layout-none parent")
    func groupIsOffsetInItsParent() throws {
        let code = try body(child: group(keys: ##""x": 30, "y": 40"##, children: [rect(id: "a", x: 0, y: 0)]), layout: "none")
        #expect(code.contains("}\n            .offset(x: 30, y: 40)"))
    }

    @Test("A rotated group turns about its anchor, with no bounding-box frame")
    func rotatedGroup() throws {
        let code = try body(child: group(keys: ##""rotation": -315"##, children: [rect(id: "a", x: 0, y: 0)]))
        #expect(code.contains("}\n            .rotationEffect(.degrees(315), anchor: .topLeading)"))
        // One frame for the rectangle, one for the sizeless layout-none board, which Pen
        // settles at 0×0 (leaf Jg0BOv) — none for the group.
        #expect(code.components(separatedBy: ".frame(").count == 3)
        #expect(code.components(separatedBy: ".frame(width: 0, height: 0, alignment: .topLeading)").count == 2)
    }

    @Test("A group in a stack is a PenGroupFlow of its children at their offsets from its anchor")
    func groupInAStackIsAFlow() throws {
        let code = try body(child: group(children: [rect(id: "a", x: -10, y: -10), rect(id: "b", x: 20, y: 20)]), layout: "horizontal")
        #expect(code.contains("PenGroupFlow(offsets: [CGPoint(x: -10, y: -10), CGPoint(x: 20, y: 20)]) {\n"))
        #expect(!code.contains(".padding(.leading, 20)"))
        #expect(!code.contains(".offset(x: -10"))
    }

    @Test("A turned group in a stack grows its slot to the turned union and turns about its center")
    func turnedGroupInAStack() throws {
        let code = try body(
            child: group(keys: ##""rotation": 30"##, children: [rect(id: "a", x: 0, y: 0)]), layout: "vertical"
        )
        #expect(code.contains("PenGroupFlow(offsets: [CGPoint(x: 0, y: 0)], rotation: 30) {"))
        #expect(code.contains(".rotationEffect(.degrees(-30))\n"))
        #expect(!code.contains("anchor: .topLeading"))
    }

    // MARK: - Layer effects

    @Test("A translucent group is composited before its opacity, so it fades as one layer")
    func opacityIsWholeGroup() throws {
        let code = try body(child: group(keys: ##""opacity": 0.5"##, children: [rect(id: "a", x: 0, y: 0), rect(id: "b", x: 5, y: 5)]))
        let composite = try #require(code.range(of: ".compositingGroup()"))
        let opacity = try #require(code.range(of: ".opacity(0.5)"))
        #expect(composite.lowerBound < opacity.lowerBound)
    }

    @Test("A group's blend mode is emitted outermost, after its opacity, on the composited group")
    func blendModeIsWholeGroup() throws {
        let code = try body(child: group(keys: ##""opacity": 0.5, "blendMode": "multiply""##, children: [rect(id: "a", x: 0, y: 0)]))
        let composite = try #require(code.range(of: ".compositingGroup()"))
        let opacity = try #require(code.range(of: ".opacity(0.5)"))
        let blend = try #require(code.range(of: ".blendMode(.multiply)"))
        #expect(composite.lowerBound < opacity.lowerBound)
        #expect(opacity.lowerBound < blend.lowerBound)
    }

    @Test("A group's layer blur blurs the whole group")
    func layerBlur() throws {
        let code = try body(child: group(keys: ##""effect": {"type": "blur", "radius": 8}"##, children: [rect(id: "a", x: 0, y: 0)]))
        #expect(code.contains("}\n            .blur(radius: 4)"))
    }

    @Test("A group's background blur is left out with a warning")
    func backgroundBlurWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        let keys = ##""effect": {"type": "background_blur", "radius": 8}"##
        let code = try body(child: group(keys: keys, children: [rect(id: "a", x: 0, y: 0)]), diagnostics: diagnostics)
        #expect(!code.contains("penBackgroundBlur"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "g" && $0.message.contains("background blur on groups") })
    }

    // MARK: - Shadows

    @Test("A group's outer shadow is cast by a silhouette of its children in opaque black")
    func outerShadowSilhouette() throws {
        let effect = ##""effect": {"type": "shadow", "color": "#000000A0", "offset": {"x": 8, "y": 10}, "blur": 12}"##
        let ghost = ##"{"type": "rectangle", "id": "a", "x": 0, "y": 0, "width": 80, "height": 80, "fill": "#FF000040"}"##
        let code = try body(child: group(keys: effect, children: [ghost]))
        #expect(code.contains(
            ".penGroupShadows(outer: [PenShadowStyle(color: Color(hex: 0x000000, opacity: 0.627), radius: 6, x: 8, y: 10)]) {"
        ))
        let silhouette = try #require(code.range(of: ".penGroupShadows"))
        #expect(code[silhouette.upperBound...].contains(".fill(Color(hex: 0x000000))"))
    }

    @Test("A child's own shadow, opacity and blend mode are not part of the silhouette")
    func childEffectsCastNothing() throws {
        let effect = ##""effect": {"type": "shadow", "color": "#0000FF", "blur": 4}"##
        let chip = ##"{"type": "rectangle", "id": "a", "width": 70, "height": 70, "fill": "#EEEEEE", "opacity": 0.5, "blendMode": "screen", "effect": {"type": "shadow", "color": "#FF0000", "offset": {"x": -16, "y": 0}, "blur": 4}}"##
        let code = try body(child: group(keys: effect, children: [chip]))
        let silhouette = try #require(code.range(of: ".penGroupShadows"))
        let tail = String(code[silhouette.upperBound...])
        #expect(!tail.contains("0xFF0000"))
        #expect(!tail.contains(".opacity(0.5)"))
        #expect(!tail.contains(".blendMode(.screen)"))
    }

    @Test("A line casts no part of its group's shadow; a stroke that reaches outside does, in black")
    func lineAndStroke() throws {
        let effect = ##""effect": {"type": "shadow", "color": "#0044FFCC", "offset": {"x": 0, "y": 12}, "blur": 6}"##
        let framed = ##"{"type": "rectangle", "id": "a", "width": 60, "height": 60, "fill": "#FFFFFF", "stroke": "#333333", "strokeWidth": 8, "strokeAlignment": "outer"}"##
        let line = ##"{"type": "line", "id": "l", "x": 10, "y": 110, "width": 120, "height": 0, "stroke": "#008888", "strokeWidth": 6}"##
        let code = try body(child: group(keys: effect, children: [framed, line]))
        let silhouette = try #require(code.range(of: ".penGroupShadows"))
        let tail = String(code[silhouette.upperBound...])
        #expect(!tail.contains("0x008888"))
        #expect(!tail.contains(".padding(.top, 110)"))
        #expect(!tail.contains("0x333333"))
        #expect(tail.components(separatedBy: "Color(hex: 0x000000)").count >= 3)
    }

    @Test("A frame child casts its box: its own children are not part of the silhouette")
    func frameChildCastsItsBox() throws {
        let effect = ##""effect": {"type": "shadow", "color": "#000000", "blur": 4}"##
        let overhang = ##"{"type": "rectangle", "id": "o", "x": 50, "y": 50, "width": 70, "height": 50, "fill": "#CC6600"}"##
        let card = ##"{"type": "frame", "id": "c", "width": 80, "height": 80, "layout": "none", "fill": "#DDDDDD", "children": [\##(overhang)]}"##
        let code = try body(child: group(keys: effect, children: [card]))
        let silhouette = try #require(code.range(of: ".penGroupShadows"))
        let tail = String(code[silhouette.upperBound...])
        #expect(!tail.contains("0xCC6600"))
        #expect(!tail.contains("width: 70, height: 50"))
        #expect(tail.contains("width: 80, height: 80"))
    }

    @Test("A nested group's children cast the outer group's shadow; the nested group's own shadow does not")
    func nestedGroup() throws {
        let innerEffect = ##""effect": {"type": "shadow", "color": "#FF8800", "blur": 2}"##
        let inner = group(id: "n", keys: ##""x": 80, "y": 20, \##(innerEffect)"##, children: [rect(id: "b", x: 0, y: 0)])
        let effect = ##""effect": {"type": "shadow", "color": "#000000", "blur": 16}"##
        let code = try body(child: group(keys: effect, children: [rect(id: "a", x: 0, y: 0), inner]))
        let silhouette = try #require(code.range(of: ".penGroupShadows(outer: [PenShadowStyle(color: Color(hex: 0x000000), radius: 8)])"))
        let tail = String(code[silhouette.upperBound...])
        #expect(!tail.contains("0xFF8800"))
        #expect(tail.contains(".padding(.leading, 80)"))
    }

    @Test("A group's inner shadow falls inside its silhouette, over its children")
    func innerShadow() throws {
        let effect = ##""effect": {"type": "shadow", "shadowType": "inner", "color": "#000000", "offset": {"x": 6, "y": 6}, "blur": 10}"##
        let code = try body(child: group(keys: effect, children: [rect(id: "a", x: 0, y: 0)]))
        #expect(code.contains(".penGroupShadows(inner: [PenShadowStyle(color: Color(hex: 0x000000), radius: 5, x: 6, y: 6)]) {"))
    }

    @Test("A group of lines alone has no silhouette, and so no shadow modifier")
    func noSilhouette() throws {
        let effect = ##""effect": {"type": "shadow", "color": "#000000", "blur": 4}"##
        let line = ##"{"type": "line", "id": "l", "width": 120, "height": 0, "stroke": "#008888", "strokeWidth": 6}"##
        let code = try body(child: group(keys: effect, children: [line]))
        #expect(code.contains("ZStack(alignment: .topLeading) {"))
        #expect(!code.contains("penGroupShadows"))
    }

    @Test("The support file defines the group shadow modifier and its style")
    func supportDefinesGroupShadows() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+Group.swift"])
        #expect(support.contains("struct PenShadowStyle"))
        #expect(support.contains("func penGroupShadows("))
    }

    @Test("The support file defines the layout a group in a stack uses")
    func supportDefinesGroupFlow() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+GroupFlow.swift"])
        #expect(support.contains("struct PenGroupFlow: Layout"))
    }

    // MARK: - Helpers

    private func rect(id: String, x: Double, y: Double) -> String {
        ##"{"type": "rectangle", "id": "\##(id)", "x": \##(x), "y": \##(y), "width": 10, "height": 10, "fill": "#FF0000"}"##
    }

    private func group(id: String = "g", keys: String = "", children: [String]) -> String {
        let extra = keys.isEmpty ? "" : ", \(keys)"
        return ##"{"type": "group", "id": "\##(id)"\##(extra), "children": [\##(children.joined(separator: ", "))]}"##
    }

    /// Emit a document whose root frame holds `child`, and return the page's source.
    ///
    /// The root lays its child out at its own `x`/`y` unless a test asks for a stack: a group
    /// in a stack is a different view (``groupInAStackIsAFlow()``). Until leaf cqBw2i the
    /// default was a horizontal stack, where a group was emitted the same way.
    private func body(child: String, layout: String = "none", diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "layout": "\##(layout)", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
