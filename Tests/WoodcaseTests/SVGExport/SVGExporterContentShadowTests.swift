#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// How an SVG export casts an outer shadow from a node's painted content, as the CG
    /// renderer does (`pen` CLI 0.3.13's rule, <doc:PenRendering>, *Shadows*): a frame's
    /// children cast with it, clipped where it clips; a line casts its stroke; a group's
    /// descendants cast through it, lines and frames' children included; and a spread grows
    /// only the node's own path.
    struct SVGExporterContentShadowTests {
        private typealias Fixture = SVGExportFixture

        private static let shadow = ##"{"type": "shadow", "shadowType": "outer", "blur": 4, "color": "#00000080", "offset": {"x": 0, "y": 4}}"##

        /// The elements an outer shadow's filter is applied to.
        private func casters(_ xml: XMLDocument) throws -> [XMLElement] {
            let shadowIDs = try Fixture.elements("filter", in: xml).compactMap { filter -> String? in
                guard try !(filter.nodes(forXPath: ".//*[local-name()='feOffset']")).isEmpty else { return nil }
                return Fixture.attribute("id", of: filter)
            }
            return try xml.nodes(forXPath: "//*[@filter]").compactMap { $0 as? XMLElement }.filter { element in
                shadowIDs.contains { Fixture.attribute("filter", of: element) == "url(#\($0))" }
            }
        }

        /// The `path` elements inside `element`.
        private func paths(in element: XMLElement) throws -> [XMLElement] {
            try element.nodes(forXPath: ".//*[local-name()='path']").compactMap { $0 as? XMLElement }
                + (element.localName == "path" ? [element] : [])
        }

        @Test("A fill-less frame's shadow is cast by its children")
        func frameChildrenCast() throws {
            let fixture = try Fixture("""
            [{"type": "frame", "id": "f", "width": 100, "height": 100, "layout": "none", "effect": \(Self.shadow),
              "children": [{"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 30, "height": 30, "fill": "#FF0000"},
                           {"type": "ellipse", "id": "b", "x": 50, "y": 50, "width": 30, "height": 30, "fill": "#0000FF"}]}]
            """)
            let xml = try #require(try fixture.svg(["f"]))
            let caster = try #require(try casters(xml).first, "the frame casts a shadow")
            #expect(try paths(in: caster).count == 2, "both children's silhouettes cast it")
        }

        @Test("A clipping frame's children cast through its clip")
        func clippingFrameClipsSilhouette() throws {
            let fixture = try Fixture("""
            [{"type": "frame", "id": "f", "width": 100, "height": 100, "layout": "none", "clip": true, "effect": \(Self.shadow),
              "children": [{"type": "rectangle", "id": "a", "x": 60, "y": 60, "width": 80, "height": 80, "fill": "#FF0000"}]}]
            """)
            let xml = try #require(try fixture.svg(["f"]))
            let caster = try #require(try casters(xml).first, "the frame casts a shadow")
            let clipped = try caster.nodes(forXPath: ".//*[@clip-path]")
            #expect(!clipped.isEmpty, "the child's silhouette is cut to the frame")
            #expect(Fixture.attribute("clip-path", of: caster) == nil, "the clip cuts the silhouette, not the shadow")
        }

        @Test("A line casts its stroke")
        func lineCasts() throws {
            let fixture = try Fixture("""
            [{"type": "line", "id": "l", "width": 100, "height": 40, "stroke": "#000000", "strokeWidth": 4, "effect": \(Self.shadow)}]
            """)
            let xml = try #require(try fixture.svg(["l"]))
            let caster = try #require(try casters(xml).first, "the line casts a shadow")
            #expect(try paths(in: caster).count == 1)
        }

        @Test("A fill-less text casts its glyphs' shadow, and draws nothing else")
        func filllessTextCasts() throws {
            let fixture = try Fixture("""
            [{"type": "text", "id": "t", "content": "Shadow", "fontFamily": "Inter", "fontSize": 20, "effect": \(Self.shadow)}]
            """)
            let xml = try #require(try fixture.svg(["t"]))
            let caster = try #require(try casters(xml).first, "the glyphs cast a shadow")
            #expect(caster.localName == "text", "the glyphs are the silhouette")
            #expect(try Fixture.elements("text", in: xml).count == 1, "only the silhouette sets the glyphs")
        }

        @Test("A fill-less text's inner shadow still falls inside its glyphs, as the CG renderer draws it")
        func filllessTextInnerShadow() throws {
            let inner = Self.shadow.replacingOccurrences(of: #""outer""#, with: #""inner""#)
            let fixture = try Fixture("""
            [{"type": "text", "id": "t", "content": "Shadow", "fontFamily": "Inter", "fontSize": 20, "effect": \(inner)}]
            """)
            let xml = try #require(try fixture.svg(["t"]))
            #expect(try !Fixture.elements("feOffset", in: xml).isEmpty, "the inner shadow is drawn")
        }

        @Test("A fill-less icon casts its glyph's shadow, and draws nothing else")
        func filllessIconCasts() throws {
            let fixture = try Fixture("""
            [{"type": "icon", "id": "i", "library": "lucide", "icon": "heart", "width": 24, "height": 24, "effect": \(Self.shadow)}]
            """)
            let xml = try #require(try fixture.svg(["i"]))
            let caster = try #require(try casters(xml).first, "the glyph casts a shadow")
            #expect(try paths(in: caster).count == 1)
            #expect(try Fixture.elements("path", in: xml).count == 1, "only the silhouette draws the glyph")
        }

        @Test("A group's line and its frame's children cast its shadow")
        func groupDescendantsCast() throws {
            let fixture = try Fixture("""
            [{"type": "group", "id": "g", "effect": \(Self.shadow), "children": [
              {"type": "line", "id": "l", "x": 0, "y": 0, "width": 100, "height": 0, "stroke": "#000000", "strokeWidth": 4},
              {"type": "frame", "id": "f", "x": 0, "y": 20, "width": 60, "height": 60, "layout": "none",
               "children": [{"type": "rectangle", "id": "r", "x": 10, "y": 10, "width": 20, "height": 20, "fill": "#FF0000"}]}]}]
            """)
            let xml = try #require(try fixture.svg(["g"]))
            let caster = try #require(try casters(xml).first, "the group casts a shadow")
            #expect(try paths(in: caster).count == 2, "the line and the frame's child cast it; the fill-less frame does not")
        }

        @Test("A spread grows the frame's own path, not its children, and the shadow is knocked out under the ungrown silhouette")
        func spreadGrowsOwnPathOnly() throws {
            let fixture = try Fixture("""
            [{"type": "frame", "id": "f", "width": 100, "height": 100, "layout": "none", "fill": "#FFFFFF", "effect": \(Self.shadow),
              "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [{"effect": 0, "spread": 6, "shadow": \(Self.shadow)}]}},
              "children": [{"type": "rectangle", "id": "a", "x": 150, "y": 10, "width": 30, "height": 30, "fill": "#FF0000"}]}]
            """)
            let xml = try #require(try fixture.svg(["f"]))
            #expect(try Fixture.elements("feMorphology", in: xml).isEmpty, "the spread is geometric, so the children are not grown")
            let caster = try #require(try casters(xml).first)
            let silhouettes = try paths(in: caster).compactMap { Fixture.attribute("d", of: $0) }
            #expect(silhouettes.count == 2)
            #expect(silhouettes.contains { $0.contains("-6") }, "the frame's own path is grown by 6: \(silhouettes)")
            let masks = try Fixture.elements("mask", in: xml)
            #expect(masks.count == 1, "the shadow is knocked out under the ungrown silhouette")
        }
    }

#endif
